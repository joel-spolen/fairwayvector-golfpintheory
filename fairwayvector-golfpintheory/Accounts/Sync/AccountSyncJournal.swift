import Foundation
import Darwin

/// Downloading a record into the journal is not the same as restoring it into
/// the app's stores. A new or interrupted device must never delete by absence.
nonisolated enum AccountSyncRestorePolicy {
    static func canInferDeletion(recordID: UUID, materializedIDs: Set<UUID>) -> Bool {
        materializedIDs.contains(recordID)
    }

    static func isUnchangedPut(_ mutation: AccountSyncMutation, previous: AccountSyncLocalRecord?) -> Bool {
        mutation.operation == .put && previous == AccountSyncLocalRecord(mutation: mutation)
    }

    static func expectedRevision(for mutation: AccountSyncMutation, serverRecord: AccountSyncRecord?,
                                 restoreDeleted: Bool) -> AccountSyncRevision {
        if mutation.operation == .put, restoreDeleted, let serverRecord, serverRecord.deletedAt != nil {
            return serverRecord.revision
        }
        return .zero
    }
}

/// This snapshot IS the foundation's local data, not a snapshot of any existing app store.
nonisolated struct AccountSyncLocalRecord: Codable, Sendable, Equatable {
    let recordID: UUID
    let kind: AccountSyncRecordKind
    let schemaVersion: Int
    let payload: [String: JSONValue]
    let isDeleted: Bool

    init(mutation: AccountSyncMutation) {
        recordID = mutation.recordID; kind = mutation.kind; schemaVersion = mutation.schemaVersion
        payload = mutation.payload; isDeleted = mutation.operation == .delete
    }
    init(record: AccountSyncRecord) {
        recordID = record.recordID; kind = record.kind; schemaVersion = record.schemaVersion
        payload = record.payload; isDeleted = record.deletedAt != nil
    }
}

nonisolated struct AccountSyncJournalEntry: Codable, Sendable, Equatable {
    let mutation: AccountSyncMutation
    var result: AccountSyncMutationResult?
    // History is never discarded; a resolution is a NEW immutable mutation.
    var resolutionMutationID: UUID?
}

nonisolated struct AccountSyncConflict: Sendable, Equatable {
    let local: AccountSyncMutation
    let server: AccountSyncMutationResult
}

nonisolated struct AccountSyncJournalSnapshot: Codable, Sendable, Equatable {
    let journalVersion: Int
    let schemaVersion: Int
    let ownerID: UUID
    var localRecords: [AccountSyncLocalRecord]
    var serverRecords: [AccountSyncRecord]
    var entries: [AccountSyncJournalEntry]
    var after: AccountSyncRevision
    var through: AccountSyncRevision?

    var pending: [AccountSyncMutation] { entries.filter { $0.result == nil }.map(\.mutation) }
    var conflicts: [AccountSyncConflict] {
        entries.compactMap { entry in
            guard let result = entry.result, !result.isApplied, entry.resolutionMutationID == nil else { return nil }
            return AccountSyncConflict(local: entry.mutation, server: result)
        }
    }

    fileprivate func validate(ownerID: UUID) throws {
        guard self.ownerID == ownerID, journalVersion == 1, schemaVersion == 1,
              through == nil || after < through!,
              Set(localRecords.map(\.recordID)).count == localRecords.count,
              Set(serverRecords.map(\.recordID)).count == serverRecords.count,
              Set(entries.map { $0.mutation.mutationID }).count == entries.count else {
            throw AccountSyncError.invalidJournal
        }
        for record in serverRecords { try record.validate() }
        for record in localRecords {
            guard record.schemaVersion == 1 else { throw AccountSyncError.invalidJournal }
            try AccountSyncMutation.validatePayload(record.payload, kind: record.kind)
        }
        var protectedIDs = Set<UUID>()
        for entry in entries {
            try entry.mutation.validate()
            if let result = entry.result {
                try result.validate(for: entry.mutation)
                for record in result.records {
                    guard let retained = serverRecords.first(where: { $0.recordID == record.recordID }),
                          retained.kind == record.kind, retained.revision >= record.revision else {
                        throw AccountSyncError.invalidJournal
                    }
                }
            }
            if let resolution = entry.resolutionMutationID {
                guard let result = entry.result, !result.isApplied,
                      let replacement = entries.first(where: { $0.mutation.mutationID == resolution }),
                      replacement.mutation.recordID == entry.mutation.recordID,
                      replacement.mutation.mutationID != entry.mutation.mutationID else {
                    throw AccountSyncError.invalidJournal
                }
            }
            if entry.result == nil || (entry.result?.isApplied == false && entry.resolutionMutationID == nil) {
                guard protectedIDs.insert(entry.mutation.recordID).inserted,
                      localRecords.first(where: { $0.recordID == entry.mutation.recordID }) == AccountSyncLocalRecord(mutation: entry.mutation) else {
                    throw AccountSyncError.invalidJournal
                }
            }
        }
        for local in localRecords where !protectedIDs.contains(local.recordID) {
            guard let server = serverRecords.first(where: { $0.recordID == local.recordID }),
                  local == AccountSyncLocalRecord(record: server) else { throw AccountSyncError.invalidJournal }
        }
    }

    fileprivate mutating func retainServer(_ record: AccountSyncRecord) throws {
        if let index = serverRecords.firstIndex(where: { $0.recordID == record.recordID }) {
            let previous = serverRecords[index]
            guard previous.kind == record.kind else { throw AccountSyncError.invalidWire }
            if previous.revision == record.revision {
                guard previous == record else { throw AccountSyncError.invalidWire }
            } else if previous.revision < record.revision {
                serverRecords[index] = record
            }
        } else { serverRecords.append(record) }
    }

    fileprivate mutating func refreshLocal(_ id: UUID) {
        guard !pending.contains(where: { $0.recordID == id }),
              !conflicts.contains(where: { $0.local.recordID == id }),
              let server = serverRecords.first(where: { $0.recordID == id }) else { return }
        replaceLocal(AccountSyncLocalRecord(record: server))
    }

    fileprivate mutating func replaceLocal(_ local: AccountSyncLocalRecord) {
        if let index = localRecords.firstIndex(where: { $0.recordID == local.recordID }) { localRecords[index] = local }
        else { localRecords.append(local) }
    }
}

/// A UUID-scoped, single-file transaction store. Every access revalidates disk under
/// an advisory lock (also serializes multiple cooperating instances/processes).
/// .atomic replaces one file containing BOTH local data and mutation/cursor history.
/// No tokens, auth sessions, logs, app-store callbacks, or destructive recovery.
nonisolated final class AccountSyncJournal: Sendable {
    let ownerID: UUID
    let fileURL: URL
    private let lockURL: URL

    /// root must be a dedicated, durable Application Support directory, never Caches.
    /// An injected temporary root is suitable for offline tests.
    init(ownerID: UUID, root: URL) throws {
        guard root.isFileURL else { throw AccountSyncError.storageUnavailable }
        self.ownerID = ownerID
        let directory = root.appendingPathComponent(ownerID.uuidString.lowercased(), isDirectory: true)
        fileURL = directory.appendingPathComponent("sync-v1.json")
        lockURL = directory.appendingPathComponent("sync-v1.lock")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try access(createIfMissing: true) { _ in }
        } catch let error as AccountSyncError { throw error }
        catch { throw AccountSyncError.storageUnavailable }
    }

    func snapshot() throws -> AccountSyncJournalSnapshot { try access { $0 } }

    /// Same ID + exact request is a no-op forever, including after acknowledgement.
    /// One outstanding mutation/conflict per record; callers must wait or explicitly resolve.
    func enqueue(_ mutation: AccountSyncMutation) throws {
        try transaction { snapshot in try Self.enqueue(mutation, into: &snapshot) }
    }

    /// Retains BOTH the submitted request and the full server response atomically.
    func acknowledge(_ result: AccountSyncMutationResult) throws {
        try transaction { snapshot in
            guard let index = snapshot.entries.firstIndex(where: { $0.mutation.mutationID == result.mutationID }) else {
                throw AccountSyncError.staleOperation
            }
            let entry = snapshot.entries[index]
            try result.validate(for: entry.mutation)
            if let previous = entry.result {
                guard previous == result else { throw AccountSyncError.invalidWire }
                return
            }
            for record in result.records { try snapshot.retainServer(record) }
            snapshot.entries[index].result = result
            // A conflicting local delete/put remains visible. Never replace it with remote data.
            snapshot.refreshLocal(entry.mutation.recordID)
            // A source_conflict can also carry a newer version of an already cached
            // linked HCP record. Keep that cache coherent, without installing a new
            // local HCP entry merely because an import attempt conflicted.
            for record in result.records where record.recordID != entry.mutation.recordID {
                if snapshot.localRecords.contains(where: { $0.recordID == record.recordID }) {
                    snapshot.refreshLocal(record.recordID)
                }
            }
        }
    }

    /// Explicit manual replacement only. No automatic restore, merge, or HCP import.
    /// The caller supplies a new mutation ID and the latest observed CAS revision.
    func resolveConflict(mutationID: UUID, with replacement: AccountSyncMutation) throws {
        try transaction { snapshot in
            guard let index = snapshot.entries.firstIndex(where: { $0.mutation.mutationID == mutationID }),
                  let result = snapshot.entries[index].result, !result.isApplied else {
                throw AccountSyncError.staleOperation
            }
            if let resolved = snapshot.entries[index].resolutionMutationID {
                guard resolved == replacement.mutationID,
                      snapshot.entries.contains(where: { $0.mutation == replacement }) else { throw AccountSyncError.staleOperation }
                return
            }
            let original = snapshot.entries[index].mutation
            let revision = snapshot.serverRecords.first(where: { $0.recordID == original.recordID })?.revision ?? .zero
            guard replacement.recordID == original.recordID, replacement.kind == original.kind,
                  replacement.expectedRevision == revision, replacement.mutationID != mutationID,
                  !snapshot.entries.contains(where: { $0.mutation.mutationID == replacement.mutationID }) else {
                throw AccountSyncError.staleOperation
            }
            snapshot.entries[index].resolutionMutationID = replacement.mutationID
            try Self.enqueue(replacement, into: &snapshot)
        }
    }

    func changesRequest(limit: Int = 100) throws -> AccountSyncChangesRequest {
        let state = try snapshot()
        return try AccountSyncChangesRequest(after: state.after, through: state.through, limit: limit)
    }

    /// Cursor advancement and all page records share one atomic write. A failed
    /// write leaves the old cursor and old records intact, so a retry replays safely.
    func apply(_ page: AccountSyncChangePage, for request: AccountSyncChangesRequest) throws {
        try transaction { snapshot in
            guard snapshot.after == request.after, snapshot.through == request.through else {
                throw AccountSyncError.staleOperation
            }
            try page.validate(for: request)
            for event in page.events {
                try snapshot.retainServer(event.record)
                snapshot.refreshLocal(event.record.recordID)
            }
            snapshot.after = page.hasMore ? page.nextAfter : page.through
            snapshot.through = page.hasMore ? page.through : nil
        }
    }

    private static func enqueue(_ mutation: AccountSyncMutation, into snapshot: inout AccountSyncJournalSnapshot) throws {
        try mutation.validate()
        if let existing = snapshot.entries.first(where: { $0.mutation.mutationID == mutation.mutationID }) {
            guard existing.mutation == mutation else { throw AccountSyncError.mutationIDReused }
            return
        }
        guard !snapshot.pending.contains(where: { $0.recordID == mutation.recordID }),
              !snapshot.conflicts.contains(where: { $0.local.recordID == mutation.recordID }) else {
            throw AccountSyncError.recordBusy
        }
        if let record = snapshot.localRecords.first(where: { $0.recordID == mutation.recordID }), record.kind != mutation.kind {
            throw AccountSyncError.invalidWire
        }
        snapshot.entries.append(AccountSyncJournalEntry(mutation: mutation))
        snapshot.replaceLocal(AccountSyncLocalRecord(mutation: mutation))
    }

    private func transaction(_ update: (inout AccountSyncJournalSnapshot) throws -> Void) throws {
        try access { state in
            var next = state
            try update(&next)
            try next.validate(ownerID: ownerID)
            if next != state { try write(next) }
        }
    }

    private func access<T>(createIfMissing: Bool = false, _ body: (AccountSyncJournalSnapshot) throws -> T) throws -> T {
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw AccountSyncError.storageUnavailable }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw AccountSyncError.storageUnavailable }
        defer { _ = flock(descriptor, LOCK_UN) }
        let state: AccountSyncJournalSnapshot
        // lstat sees dangling symlinks too; they are corrupt storage, not a fresh account.
        var metadata = stat()
        let exists = Darwin.lstat(fileURL.path, &metadata) == 0
        guard exists || errno == ENOENT else { throw AccountSyncError.storageUnavailable }
        if exists {
            do {
                guard metadata.st_mode & S_IFMT == S_IFREG else {
                    throw AccountSyncError.invalidJournal
                }
                state = try JSONDecoder().decode(AccountSyncJournalSnapshot.self, from: Data(contentsOf: fileURL))
                try state.validate(ownerID: ownerID)
            } catch { throw AccountSyncError.invalidJournal }
        } else {
            guard createIfMissing else { throw AccountSyncError.invalidJournal }
            state = AccountSyncJournalSnapshot(journalVersion: 1, schemaVersion: 1, ownerID: ownerID,
                localRecords: [], serverRecords: [], entries: [], after: .zero, through: nil)
            try write(state)
        }
        return try body(state)
    }

    private func write(_ state: AccountSyncJournalSnapshot) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { throw AccountSyncError.storageUnavailable }
    }
}