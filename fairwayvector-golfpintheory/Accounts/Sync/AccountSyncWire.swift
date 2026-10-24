import Foundation

/// Foundation DTOs only. No existing archive is approved for upload by these types.
nonisolated enum AccountSyncError: Error, Sendable, Equatable, LocalizedError {
    case invalidWire, invalidConfiguration, authenticationRequired, accountUnavailable
    case requestRejected, serverContractUnavailable, transportUnavailable, storageUnavailable, invalidJournal
    case mutationIDReused, recordBusy, staleOperation

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "Sign in again to sync."
        case .accountUnavailable: "This account is unavailable for sync."
        case .serverContractUnavailable: "Cloud sync is not ready on this server yet. Your saved data remains on this device."
        case .storageUnavailable, .invalidJournal: "Account sync storage is unavailable. Existing data was not replaced."
        default: "Account sync could not complete."
        }
    }
}

/// Revisions, sequences and cursors NEVER pass through a JSON number or floating point.
nonisolated struct AccountSyncRevision: Codable, Sendable, Hashable, Comparable {
    let rawValue: String
    static let zero = Self(unchecked: "0")

    init(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 19,
              bytes.allSatisfy({ (48...57).contains($0) }),
              bytes.count == 1 || bytes[0] != 48,
              bytes.count < 19 || value <= "9223372036854775807" else {
            throw AccountSyncError.invalidWire
        }
        rawValue = value
    }

    private init(unchecked value: String) { rawValue = value }
    init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue.count == rhs.rawValue.count
            ? lhs.rawValue < rhs.rawValue : lhs.rawValue.count < rhs.rawValue.count
    }
}

/// Exact decimal payload numbers: abs(value) <= 10^20 and at most 16 fractional
/// places, recursively (SQL uses value = round(value, 16)). Every allowed value
/// fits Decimal without rounding. Domain-specific DTO/field allowlists remain required.
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case null, bool(Bool), string(String), number(Decimal)
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else {
            let value = try container.decode(Decimal.self)
            try Self.validateNumber(value)
            self = .number(value)
        }
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value):
            try Self.validateNumber(value)
            try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    private static func validateNumber(_ value: Decimal) throws {
        let bound = Decimal(sign: .plus, exponent: 20, significand: 1)
        guard !value.isNaN, value >= -bound, value <= bound else {
            throw AccountSyncError.invalidWire
        }
        var original = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, 16, .plain)
        guard rounded == value else { throw AccountSyncError.invalidWire }
    }

    /// Also validate directly constructed values before an outbox/journal write;
    /// validation must not depend on a later encoder being invoked.
    func validate() throws {
        switch self {
        case .number(let value): try Self.validateNumber(value)
        case .array(let values): for value in values { try value.validate() }
        case .object(let values): for value in values.values { try value.validate() }
        case .null, .bool, .string: break
        }
    }
}

nonisolated enum AccountSyncRecordKind: String, Codable, Sendable, CaseIterable {
    case golferProfile = "golfer_profile", clubProfile = "club_profile", wedge
    case customClub = "custom_club", customCourse = "custom_course", customTee = "custom_tee"
    case playedRound = "played_round", handicapRound = "handicap_round", flagPosition = "flag_position"
}

nonisolated enum AccountSyncOperation: String, Codable, Sendable { case put, delete }

nonisolated struct AccountSyncRecord: Codable, Sendable, Equatable {
    let recordID: UUID
    let kind: AccountSyncRecordKind
    let schemaVersion: Int
    let payload: [String: JSONValue]
    let revision: AccountSyncRevision
    // Retain PostgreSQL's exact timestamp text, including fractional precision/offset.
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    nonisolated enum CodingKeys: String, CodingKey {
        case recordID = "record_id", kind, schemaVersion = "schema_version", payload, revision
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordID, forKey: .recordID)
        try container.encode(kind, forKey: .kind)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(payload, forKey: .payload)
        try container.encode(revision, forKey: .revision)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt) // Explicit JSON null, never an omitted wire key.
    }

    func validate() throws {
        guard schemaVersion == 1, revision > .zero else { throw AccountSyncError.invalidWire }
        try AccountSyncMutation.validatePayload(payload, kind: kind)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        for value in [createdAt, updatedAt] + (deletedAt.map { [$0] } ?? []) {
            guard fractional.date(from: value) != nil || plain.date(from: value) != nil else {
                throw AccountSyncError.invalidWire
            }
        }
    }
}

nonisolated struct AccountSyncMutation: Codable, Sendable, Equatable {
    let mutationID: UUID
    let recordID: UUID
    let kind: AccountSyncRecordKind
    let expectedRevision: AccountSyncRevision
    let operation: AccountSyncOperation
    let schemaVersion: Int
    let payload: [String: JSONValue]

    init(mutationID: UUID = UUID(), recordID: UUID, kind: AccountSyncRecordKind,
         expectedRevision: AccountSyncRevision, operation: AccountSyncOperation = .put,
         schemaVersion: Int = 1, payload: [String: JSONValue]) throws {
        self.mutationID = mutationID; self.recordID = recordID; self.kind = kind
        self.expectedRevision = expectedRevision; self.operation = operation
        self.schemaVersion = schemaVersion; self.payload = payload
        try validate()
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case mutationID = "p_mutation_id", recordID = "p_record_id", kind = "p_kind"
        case expectedRevision = "p_expected_revision", operation = "p_operation"
        case schemaVersion = "p_schema_version", payload = "p_payload"
    }

    func validate() throws {
        guard schemaVersion == 1, operation != .delete || payload.isEmpty else {
            throw AccountSyncError.invalidWire
        }
        try Self.validatePayload(payload, kind: kind)
    }

    static func validatePayload(_ payload: [String: JSONValue], kind: AccountSyncRecordKind) throws {
        // The backend alone enforces 65,536 bytes of PostgreSQL JSONB text.
        // Swift slash/Unicode escaping and JSONB whitespace have different sizes.
        // Never reapply an encoder-size limit to incoming records or journal data:
        // a valid server event could otherwise permanently block cursor progress.
        try JSONValue.object(payload).validate()
        if let source = payload["sourceSavedRoundID"] {
            guard kind == .handicapRound else { throw AccountSyncError.invalidWire }
            switch source {
            case .null: break
            case .string(let text):
                guard text.count == 36, UUID(uuidString: text) != nil else { throw AccountSyncError.invalidWire }
            default: throw AccountSyncError.invalidWire
            }
        }
    }
}

nonisolated enum AccountSyncMutationResult: Codable, Sendable, Equatable {
    case applied(mutationID: UUID, record: AccountSyncRecord)
    case conflict(mutationID: UUID, current: AccountSyncRecord?)
    case sourceConflict(mutationID: UUID, current: AccountSyncRecord?, sourceRecord: AccountSyncRecord)

    nonisolated enum CodingKeys: String, CodingKey { case status, mutationID = "mutation_id", record, current, sourceRecord = "source_record" }
    nonisolated enum Status: String, Codable { case applied, conflict, sourceConflict = "source_conflict" }

    var mutationID: UUID {
        switch self {
        case .applied(let id, _), .conflict(let id, _), .sourceConflict(let id, _, _): id
        }
    }
    var records: [AccountSyncRecord] {
        switch self {
        case .applied(_, let record): [record]
        case .conflict(_, let current): current.map { [$0] } ?? []
        case .sourceConflict(_, let current, let source): (current.map { [$0] } ?? []) + [source]
        }
    }
    var isApplied: Bool { if case .applied = self { true } else { false } }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .mutationID)
        switch try container.decode(Status.self, forKey: .status) {
        case .applied: self = .applied(mutationID: id, record: try container.decode(AccountSyncRecord.self, forKey: .record))
        case .conflict: self = .conflict(mutationID: id, current: try container.decode(AccountSyncRecord?.self, forKey: .current))
        case .sourceConflict:
            self = .sourceConflict(mutationID: id, current: try container.decode(AccountSyncRecord?.self, forKey: .current),
                                   sourceRecord: try container.decode(AccountSyncRecord.self, forKey: .sourceRecord))
        }
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mutationID, forKey: .mutationID)
        switch self {
        case .applied(_, let record):
            try container.encode(Status.applied, forKey: .status); try container.encode(record, forKey: .record)
        case .conflict(_, let current):
            try container.encode(Status.conflict, forKey: .status); try container.encode(current, forKey: .current)
        case .sourceConflict(_, let current, let source):
            try container.encode(Status.sourceConflict, forKey: .status)
            try container.encode(current, forKey: .current); try container.encode(source, forKey: .sourceRecord)
        }
    }

    func validate(for mutation: AccountSyncMutation) throws {
        guard mutationID == mutation.mutationID else { throw AccountSyncError.invalidWire }
        for record in records { try record.validate() }
        switch self {
        case .applied(_, let record):
            guard record.recordID == mutation.recordID, record.kind == mutation.kind,
                  record.revision > mutation.expectedRevision,
                  (record.deletedAt != nil) == (mutation.operation == .delete),
                  mutation.operation == .delete || record.payload == mutation.payload else {
                throw AccountSyncError.invalidWire
            }
        case .conflict(_, let current), .sourceConflict(_, let current, _):
            guard current == nil || current?.recordID == mutation.recordID else { throw AccountSyncError.invalidWire }
        }
        if case .sourceConflict(_, _, let source) = self {
            guard mutation.kind == .handicapRound, source.kind == .handicapRound,
                  source.recordID != mutation.recordID,
                                    let submitted = mutation.payload["sourceSavedRoundID"],
                                    let stored = source.payload["sourceSavedRoundID"],
                                    case .string(let submittedID) = submitted, case .string(let storedID) = stored,
                  UUID(uuidString: submittedID) == UUID(uuidString: storedID) else {
                throw AccountSyncError.invalidWire
            }
        }
    }
}

nonisolated struct AccountSyncChangesRequest: Codable, Sendable, Equatable {
    let after: AccountSyncRevision
    let through: AccountSyncRevision?
    let limit: Int
    init(after: AccountSyncRevision = .zero, through: AccountSyncRevision? = nil, limit: Int = 100) throws {
        guard (1...200).contains(limit), through == nil || after <= through! else { throw AccountSyncError.invalidWire }
        self.after = after; self.through = through; self.limit = limit
    }
    nonisolated enum CodingKeys: String, CodingKey { case after = "p_after", through = "p_through", limit = "p_limit" }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(after, forKey: .after)
        try container.encode(through, forKey: .through)
        try container.encode(limit, forKey: .limit)
    }
}

nonisolated struct AccountSyncChangeEvent: Codable, Sendable, Equatable {
    let sequence: AccountSyncRevision
    let record: AccountSyncRecord
}

nonisolated struct AccountSyncChangePage: Codable, Sendable, Equatable {
    let events: [AccountSyncChangeEvent]
    let nextAfter: AccountSyncRevision
    let through: AccountSyncRevision
    let hasMore: Bool
    nonisolated enum CodingKeys: String, CodingKey { case events, nextAfter = "next_after", through, hasMore = "has_more" }

    func validate(for request: AccountSyncChangesRequest) throws {
        guard (1...200).contains(request.limit), events.count <= request.limit,
              through >= request.after, request.through == nil || request.through == through else {
            throw AccountSyncError.invalidWire
        }
        var previous = request.after
        for event in events {
            try event.record.validate()
            guard event.sequence > previous, event.sequence <= through,
                  event.sequence == event.record.revision else { throw AccountSyncError.invalidWire }
            previous = event.sequence
        }
        guard nextAfter == previous, hasMore == (nextAfter < through),
              !hasMore || !events.isEmpty else { throw AccountSyncError.invalidWire }
    }
}