import Foundation
import Testing
@testable import fairwayvector_golfpintheory

/// Offline regression SOURCE ONLY. Not executed as part of phase-one implementation.
@MainActor
struct AccountSyncTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("account-sync-\(UUID().uuidString)", isDirectory: true)
    }
    private func payload(_ label: String) -> [String: JSONValue] { ["label": .string(label)] }
    private func mutation(id: UUID = UUID(), recordID: UUID, expected: String = "0",
                          label: String = "local", operation: AccountSyncOperation = .put) throws -> AccountSyncMutation {
        try AccountSyncMutation(mutationID: id, recordID: recordID, kind: .wedge,
            expectedRevision: AccountSyncRevision(expected), operation: operation,
            payload: operation == .delete ? [:] : payload(label))
    }
    private func record(id: UUID, revision: String, label: String = "server", deleted: Bool = false) throws -> AccountSyncRecord {
        AccountSyncRecord(recordID: id, kind: .wedge, schemaVersion: 1, payload: payload(label),
            revision: try AccountSyncRevision(revision), createdAt: "2026-10-19T12:00:00+00:00",
            updatedAt: "2026-10-19T12:00:01.123456+00:00", deletedAt: deleted ? "2026-10-19T12:00:01+00:00" : nil)
    }

    @Test func wireRevisionsAreStrictDecimalStringsWithoutPrecisionLoss() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        for text in ["0", "1", "9007199254740993", "9223372036854775807"] {
            let value = try decoder.decode(AccountSyncRevision.self, from: Data("\"\(text)\"".utf8))
            #expect(value.rawValue == text)
            #expect(String(decoding: try encoder.encode(value), as: UTF8.self) == "\"\(text)\"")
        }
        for text in ["", "00", "01", "-1", "+1", "1.0", "1e3", " 1", "١", "9223372036854775808"] {
            #expect(throws: AccountSyncError.self) { try AccountSyncRevision(text) }
        }
        for json in ["1", "9007199254740993", "null", "true"] {
            #expect(throws: (any Error).self) { try decoder.decode(AccountSyncRevision.self, from: Data(json.utf8)) }
        }
        #expect(try AccountSyncRevision("9") < AccountSyncRevision("10"))
        #expect(try AccountSyncRevision("9007199254740992") < AccountSyncRevision("9007199254740993"))
    }

    @Test func rpcKeysAndNullThroughMatchContract() throws {
        let input = try mutation(recordID: UUID(), expected: "9007199254740993")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        #expect(Set(object.keys) == Set(["p_mutation_id", "p_record_id", "p_kind", "p_expected_revision", "p_operation", "p_schema_version", "p_payload"]))
        #expect(object["p_expected_revision"] as? String == "9007199254740993")
        #expect(object["p_schema_version"] as? Int == 1)
        #expect(object["p_kind"] as? String == "wedge")
        let request = try AccountSyncChangesRequest()
        let changes = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(changes["p_after"] as? String == "0")
        #expect(changes["p_through"] is NSNull)
        #expect(changes["p_limit"] as? Int == 100)
        #expect(AccountSyncRecordKind.allCases.count == 9)
    }

    @Test func jsonPayloadAndAllResultAlternativesRoundTrip() throws {
        let value: JSONValue = .object(["null": .null, "bool": .bool(true), "text": .string("value"),
            "number": .number(Decimal(string: "9007199254740993.125")!), "list": .array([.number(2), .object([:])])])
        #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) == value)
        let id = UUID()
        let server = try record(id: UUID(), revision: "1")
        let envelope = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(server)) as? [String: Any])
        #expect(envelope["deleted_at"] is NSNull)
        #expect(envelope["revision"] as? String == "1")
        let alternatives: [AccountSyncMutationResult] = [
            .applied(mutationID: id, record: server), .conflict(mutationID: id, current: nil),
            .conflict(mutationID: id, current: server), .sourceConflict(mutationID: id, current: nil, sourceRecord: server)
        ]
        for result in alternatives {
            #expect(try JSONDecoder().decode(AccountSyncMutationResult.self, from: JSONEncoder().encode(result)) == result)
        }
        #expect(throws: AccountSyncError.self) {
            try AccountSyncMutation(recordID: UUID(), kind: .wedge, expectedRevision: .zero,
                                    operation: .delete, payload: payload("not empty"))
        }
        #expect(throws: AccountSyncError.self) {
            try AccountSyncMutation(recordID: UUID(), kind: .wedge, expectedRevision: .zero,
                                    payload: ["sourceSavedRoundID": .null])
        }
    }

    @Test func payloadNumbersPreserveSharedExactDecimalBoundariesRecursively() throws {
        let accepted = ["0", "-0", "1e20", "-1e20", "1e-16", "-1e-16",
            "9007199254740993.125", "57.6234567890123456", "-12.0123456789012345",
            "99999999999999999999.9999999999999999",
            "-99999999999999999999.9999999999999999", "1.23000000000000000"]
        for text in accepted {
            let decimal = try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
            let json = Data("{\"nested\":[true,null,{\"value\":\(text)}]}".utf8)
            let value = try JSONDecoder().decode(JSONValue.self, from: json)
            let expected: JSONValue = .object(["nested": .array([.bool(true), .null,
                .object(["value": .number(decimal)])])])
            #expect(value == expected)
            try value.validate()
            #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) == expected)
            let input = try AccountSyncMutation(recordID: UUID(), kind: .flagPosition,
                expectedRevision: .zero, payload: ["nested": value])
            #expect(try JSONDecoder().decode(AccountSyncMutation.self, from: JSONEncoder().encode(input)) == input)
        }
        // JSON booleans remain booleans, not Decimal(0)/Decimal(1).
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data("true".utf8)) == .bool(true))
    }

    @Test func payloadNumbersRejectOutOfDomainBeforeEncodingOrPersistence() throws {
        let rejected = ["1e200", "-1e200", "100000000000000000001", "-100000000000000000001",
            "1e-17", "-1e-17", "57.12345678901234567"]
        for text in rejected {
            for json in [text, "[\(text)]", "{\"nested\":[{\"value\":\(text)}]}"] {
                #expect(throws: (any Error).self) {
                    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
                }
            }
        }
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let before = try Data(contentsOf: journal.fileURL)
        for decimal in [Decimal.nan, Decimal(sign: .plus, exponent: 21, significand: 1),
                        Decimal(sign: .minus, exponent: -17, significand: 1)] {
            let invalid: JSONValue = .object(["nested": .array([.object(["value": .number(decimal)])])])
            #expect(throws: AccountSyncError.invalidWire) { try invalid.validate() }
            #expect(throws: AccountSyncError.invalidWire) { try JSONEncoder().encode(invalid) }
            #expect(throws: AccountSyncError.invalidWire) {
                try AccountSyncMutation(recordID: UUID(), kind: .wedge, expectedRevision: .zero,
                    payload: ["invalid": invalid])
            }
            let remote = AccountSyncRecord(recordID: UUID(), kind: .wedge, schemaVersion: 1,
                payload: ["invalid": invalid], revision: try AccountSyncRevision("1"),
                createdAt: "2026-10-19T12:00:00+00:00", updatedAt: "2026-10-19T12:00:00+00:00", deletedAt: nil)
            #expect(throws: AccountSyncError.invalidWire) {
                try journal.apply(AccountSyncChangePage(events: [.init(sequence: remote.revision, record: remote)],
                    nextAfter: remote.revision, through: remote.revision, hasMore: false), for: journal.changesRequest())
            }
            #expect(try Data(contentsOf: journal.fileURL) == before)
        }
    }

    @Test func serverSizedSlashPayloadSurvivesReceiptPullAndJournalReopen() throws {
        // PostgreSQL {"label": "..."} is exactly 65,536 UTF-8 bytes. Swift's
        // default escaped slashes exceed that limit despite identical JSON values.
        let text = String(repeating: "/", count: 65_536 - 13)
        #expect(Data("{\"label\": \"\(text)\"}".utf8).count == 65_536)
        let contents = payload(text)
        #expect(try JSONEncoder().encode(contents).count > 65_536)
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), id = UUID()
        let journal = try AccountSyncJournal(ownerID: owner, root: directory)
        let input = try AccountSyncMutation(recordID: id, kind: .wedge, expectedRevision: .zero, payload: contents)
        try journal.enqueue(input)
        let first = try record(id: id, revision: "1", label: text)
        let receipt = AccountSyncMutationResult.applied(mutationID: input.mutationID, record: first)
        let serverEncoder = JSONEncoder()
        serverEncoder.outputFormatting = [.withoutEscapingSlashes]
        try journal.acknowledge(JSONDecoder().decode(AccountSyncMutationResult.self, from: serverEncoder.encode(receipt)))
        var reopened = try AccountSyncJournal(ownerID: owner, root: directory)
        #expect(try reopened.snapshot().pending.isEmpty)
        #expect(try reopened.snapshot().serverRecords == [first])
        let second = try record(id: id, revision: "2", label: text)
        let page = AccountSyncChangePage(events: [.init(sequence: first.revision, record: first),
            .init(sequence: second.revision, record: second)], nextAfter: second.revision,
            through: second.revision, hasMore: false)
        let decoded = try JSONDecoder().decode(AccountSyncChangePage.self, from: serverEncoder.encode(page))
        try reopened.apply(decoded, for: reopened.changesRequest())
        reopened = try AccountSyncJournal(ownerID: owner, root: directory)
        #expect(try reopened.snapshot().after == second.revision)
        #expect(try reopened.snapshot().localRecords.first?.payload == contents)
        let next = try record(id: id, revision: "3", label: "next event")
        try reopened.apply(AccountSyncChangePage(events: [.init(sequence: next.revision, record: next)],
            nextAfter: next.revision, through: next.revision, hasMore: false), for: reopened.changesRequest())
        #expect(try reopened.snapshot().after == next.revision)
    }

    @Test func payloadSizeIsBackendAuthoritativeNotAnEncoderDependentLocalLimit() throws {
        for text in [String(repeating: "/", count: 70_000), String(repeating: "🏌️\n", count: 12_000)] {
            // Intentionally no local 65-KiB or transport-size guarantee. A server
            // rejection must remain pending, not turn into a poisoned remote feed.
            let input = try AccountSyncMutation(recordID: UUID(), kind: .wedge,
                expectedRevision: .zero, payload: payload(text))
            try input.validate()
            #expect(try JSONDecoder().decode(AccountSyncMutation.self, from: JSONEncoder().encode(input)) == input)
        }
    }

    @Test func atomicSnapshotAndPendingMutationSurviveReopenAndIDReuse() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), id = UUID()
        let journal = try AccountSyncJournal(ownerID: owner, root: directory)
        let input = try mutation(recordID: id)
        try journal.enqueue(input)
        let bytes = try Data(contentsOf: journal.fileURL)
        try journal.enqueue(input)
        #expect(try Data(contentsOf: journal.fileURL) == bytes)
        let reopened = try AccountSyncJournal(ownerID: owner, root: directory)
        let snapshot = try reopened.snapshot()
        #expect(snapshot.pending == [input])
        #expect(snapshot.localRecords == [AccountSyncLocalRecord(mutation: input)])
        let changed = try mutation(id: input.mutationID, recordID: id, label: "changed")
        #expect(throws: AccountSyncError.mutationIDReused) { try reopened.enqueue(changed) }
        #expect(try Data(contentsOf: journal.fileURL) == bytes)
        let receipt = AccountSyncMutationResult.applied(mutationID: input.mutationID,
            record: try record(id: id, revision: "1", label: "local"))
        try reopened.acknowledge(receipt)
        try reopened.enqueue(input)
        try reopened.acknowledge(receipt)
        #expect(try reopened.snapshot().pending.isEmpty)
        #expect(try reopened.snapshot().entries.count == 1)
        #expect(throws: AccountSyncError.mutationIDReused) { try reopened.enqueue(changed) }
        // No transport credential is present in the persistent schema/file.
        let stored = String(decoding: try Data(contentsOf: journal.fileURL), as: UTF8.self)
        #expect(!stored.contains("accessToken"))
        #expect(!stored.contains("Authorization"))
    }

    @Test func corruptJournalCannotBeOverwrittenByOpenOrExistingHandle() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID()
        let journal = try AccountSyncJournal(ownerID: owner, root: directory)
        let corrupt = Data("{incomplete-json".utf8)
        try corrupt.write(to: journal.fileURL, options: .atomic)
        #expect(throws: AccountSyncError.invalidJournal) { try AccountSyncJournal(ownerID: owner, root: directory) }
        #expect(throws: AccountSyncError.invalidJournal) { try journal.enqueue(mutation(recordID: UUID())) }
        #expect(try Data(contentsOf: journal.fileURL) == corrupt)
    }

    @Test func wrongOwnerAndUnsupportedVersionsFailClosed() throws {
        for key in ["ownerID", "journalVersion", "schemaVersion"] {
            let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
            let owner = UUID()
            let journal = try AccountSyncJournal(ownerID: owner, root: directory)
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal.fileURL)) as? [String: Any])
            if key == "ownerID" { object[key] = UUID().uuidString }
            else { object[key] = 99 }
            let invalid = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try invalid.write(to: journal.fileURL, options: .atomic)
            #expect(throws: AccountSyncError.invalidJournal) { try AccountSyncJournal(ownerID: owner, root: directory) }
            #expect(try Data(contentsOf: journal.fileURL) == invalid)
        }
    }

    @Test func sameRecordAndMutationUUIDAreIndependentAcrossAccounts() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let accountA = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let accountB = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let input = try mutation(recordID: UUID())
        try accountA.enqueue(input)
        #expect(try accountB.snapshot().localRecords.isEmpty)
        try accountB.enqueue(mutation(id: input.mutationID, recordID: input.recordID, label: "account B"))
        #expect(try accountA.snapshot().localRecords.first?.payload == payload("local"))
        #expect(try accountB.snapshot().localRecords.first?.payload == payload("account B"))
        #expect(accountA.fileURL != accountB.fileURL)
    }

    @Test func pullNeverOverwritesPendingAndOldReceiptCannotRegressNewerServer() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let input = try mutation(recordID: UUID())
        try journal.enqueue(input)
        let latest = try record(id: input.recordID, revision: "2", label: "new remote")
        let request = try journal.changesRequest()
        try journal.apply(AccountSyncChangePage(events: [.init(sequence: latest.revision, record: latest)],
            nextAfter: latest.revision, through: latest.revision, hasMore: false), for: request)
        #expect(try journal.snapshot().localRecords.first?.payload == input.payload)
        let older = try record(id: input.recordID, revision: "1", label: "local")
        try journal.acknowledge(.applied(mutationID: input.mutationID, record: older))
        let reopened = try AccountSyncJournal(ownerID: journal.ownerID, root: directory).snapshot()
        #expect(reopened.serverRecords == [latest])
        #expect(reopened.localRecords.first?.payload == latest.payload)
        #expect(reopened.after == latest.revision)
    }

    @Test func conflictRetainsLocalAndOriginalRemoteAcrossPullAndReopen() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let input = try mutation(recordID: UUID())
        try journal.enqueue(input)
        let original = try record(id: input.recordID, revision: "1")
        let conflict = AccountSyncMutationResult.conflict(mutationID: input.mutationID, current: original)
        try journal.acknowledge(conflict)
        let newer = try record(id: input.recordID, revision: "2", deleted: true)
        let request = try journal.changesRequest()
        try journal.apply(AccountSyncChangePage(events: [.init(sequence: newer.revision, record: newer)],
            nextAfter: newer.revision, through: newer.revision, hasMore: false), for: request)
        let reopened = try AccountSyncJournal(ownerID: journal.ownerID, root: directory)
        let state = try reopened.snapshot()
        #expect(state.pending.isEmpty)
        #expect(state.conflicts == [.init(local: input, server: conflict)])
        #expect(state.serverRecords == [newer])
        #expect(state.localRecords.first?.payload == input.payload)
        #expect(state.localRecords.first?.isDeleted == false)
        #expect(throws: AccountSyncError.recordBusy) { try reopened.enqueue(mutation(recordID: input.recordID)) }
        let resolution = try mutation(recordID: input.recordID, expected: "2", label: "manual resolution")
        try reopened.resolveConflict(mutationID: input.mutationID, with: resolution)
        try reopened.resolveConflict(mutationID: input.mutationID, with: resolution)
        #expect(try reopened.snapshot().entries.count == 2)
        #expect(try reopened.snapshot().entries.first?.result == conflict)
        #expect(try reopened.snapshot().pending == [resolution])
    }

    @Test func deleteVersusMissingConflictKeepsLocalTombstone() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let input = try mutation(recordID: UUID(), expected: "4", operation: .delete)
        try journal.enqueue(input)
        try journal.acknowledge(.conflict(mutationID: input.mutationID, current: nil))
        #expect(try journal.snapshot().localRecords.first?.isDeleted == true)
        #expect(try journal.snapshot().conflicts.first?.local == input)
    }

    @Test func sourceConflictRetainsBothServerRecordsAndLocalImport() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let sourceID = UUID()
        let input = try AccountSyncMutation(recordID: UUID(), kind: .handicapRound, expectedRevision: .zero,
            payload: ["sourceSavedRoundID": .string(sourceID.uuidString.uppercased()), "score": .number(72)])
        try journal.enqueue(input)
        let linked = AccountSyncRecord(recordID: UUID(), kind: .handicapRound, schemaVersion: 1,
            payload: ["sourceSavedRoundID": .string(sourceID.uuidString.lowercased())],
            revision: try AccountSyncRevision("1"), createdAt: "2026-10-19T12:00:00+00:00",
            updatedAt: "2026-10-19T12:00:00+00:00", deletedAt: "2026-10-19T12:00:00+00:00")
        let result = AccountSyncMutationResult.sourceConflict(mutationID: input.mutationID, current: nil, sourceRecord: linked)
        try journal.acknowledge(result)
        #expect(try journal.snapshot().conflicts == [.init(local: input, server: result)])
        #expect(try journal.snapshot().localRecords == [AccountSyncLocalRecord(mutation: input)])
        #expect(try journal.snapshot().serverRecords == [linked])
    }

    @Test func boundedPullWindowAndCursorSurviveRestart() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let first = try record(id: UUID(), revision: "1")
        let second = try record(id: first.recordID, revision: "2", deleted: true)
        let request = try journal.changesRequest(limit: 1)
        try journal.apply(AccountSyncChangePage(events: [.init(sequence: first.revision, record: first)],
            nextAfter: first.revision, through: second.revision, hasMore: true), for: request)
        let reopened = try AccountSyncJournal(ownerID: journal.ownerID, root: directory)
        let next = try reopened.changesRequest(limit: 1)
        #expect(next.after == first.revision)
        #expect(next.through == second.revision)
        try reopened.apply(AccountSyncChangePage(events: [.init(sequence: second.revision, record: second)],
            nextAfter: second.revision, through: second.revision, hasMore: false), for: next)
        let state = try reopened.snapshot()
        #expect(state.after == second.revision)
        #expect(state.through == nil)
        #expect(state.localRecords.first?.isDeleted == true)
        #expect(try reopened.changesRequest().through == nil)
        #expect(throws: AccountSyncError.staleOperation) {
            try reopened.apply(AccountSyncChangePage(events: [], nextAfter: .zero, through: .zero, hasMore: false), for: request)
        }
    }

    @Test func invalidPageAndMismatchedReceiptLeaveJournalBytesUnchanged() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let input = try mutation(recordID: UUID())
        try journal.enqueue(input)
        let before = try Data(contentsOf: journal.fileURL)
        let one = try AccountSyncRevision("1")
        #expect(throws: AccountSyncError.invalidWire) {
            try journal.apply(AccountSyncChangePage(events: [], nextAfter: .zero, through: one, hasMore: true),
                              for: journal.changesRequest())
        }
        #expect(throws: AccountSyncError.invalidWire) {
            try journal.acknowledge(.applied(mutationID: input.mutationID, record: record(id: UUID(), revision: "1")))
        }
        #expect(try Data(contentsOf: journal.fileURL) == before)
    }

    @Test func configurationRejectsInsecureURLsAndPrivilegedOrLegacyKeys() throws {
        for url in ["http://example.com", "https://user:pass@example.com", "https://example.com/path", "https://example.com?key=x"] {
            #expect(throws: AccountSyncError.invalidConfiguration) {
                try AccountSyncSupabaseConfiguration(projectURL: URL(string: url)!, publishableKey: "sb_publishable_fixture")
            }
        }
        for key in ["", "eyJlegacyJWT", "sb_secret_fixture", "sb_publishable_bad\nheader"] {
            #expect(throws: AccountSyncError.invalidConfiguration) {
                try AccountSyncSupabaseConfiguration(projectURL: URL(string: "https://example.com")!, publishableKey: key)
            }
        }
        _ = try AccountSyncSupabaseConfiguration(projectURL: URL(string: "https://example.com")!, publishableKey: "sb_publishable_fixture")
    }

    @Test func coordinatorResumesBoundedPaginationWithoutRepeatingAcknowledgedPush() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let input = try mutation(recordID: UUID())
        try journal.enqueue(input)
        let first = try record(id: input.recordID, revision: "1", label: "local")
        let second = try record(id: input.recordID, revision: "2", label: "remote edit")
        let transport = AccountSyncScriptedTransport(
            result: .applied(mutationID: input.mutationID, record: first),
            pages: [
                AccountSyncChangePage(events: [.init(sequence: first.revision, record: first)],
                    nextAfter: first.revision, through: second.revision, hasMore: true),
                AccountSyncChangePage(events: [.init(sequence: second.revision, record: second)],
                    nextAfter: second.revision, through: second.revision, hasMore: false)
            ])
        let coordinator = AccountSyncCoordinator(journal: journal, transport: transport)
        let initial = try await coordinator.synchronize(ownerID: journal.ownerID, accessToken: "offline-test-token", pageLimit: 1, pageSize: 1)
        #expect(initial.pushed == 1)
        #expect(!initial.finishedPullWindow)
        #expect(initial.durableAfter == first.revision)
        let final = try await coordinator.synchronize(ownerID: journal.ownerID, accessToken: "offline-test-token", pageLimit: 1, pageSize: 1)
        #expect(final.pushed == 0)
        #expect(final.finishedPullWindow)
        #expect(final.durableAfter == second.revision)
        #expect(try journal.snapshot().localRecords.first?.payload == second.payload)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.last?.after == first.revision)
        #expect(requests.last?.through == second.revision)
    }

    @Test func coordinatorRejectsWrongAccountAndIgnoresLateResponseAfterInvalidation() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AccountSyncJournal(ownerID: UUID(), root: directory)
        let input = try mutation(recordID: UUID())
        try journal.enqueue(input)
        let transport = AccountSyncSuspendedTransport()
        let coordinator = AccountSyncCoordinator(journal: journal, transport: transport)
        do {
            _ = try await coordinator.synchronize(ownerID: UUID(), accessToken: "offline-test-token")
            Issue.record("Wrong account was accepted")
        } catch { #expect(error as? AccountSyncError == .staleOperation) }
        let run = Task { try await coordinator.synchronize(ownerID: journal.ownerID, accessToken: "offline-test-token") }
        await transport.waitUntilStarted()
        await coordinator.invalidate()
        await transport.complete(.applied(mutationID: input.mutationID,
            record: try record(id: input.recordID, revision: "1", label: "local")))
        do {
            _ = try await run.value
            Issue.record("An invalidated run was accepted")
        } catch { #expect(error as? AccountSyncError == .staleOperation) }
        #expect(try journal.snapshot().pending == [input])
        #expect(try journal.snapshot().entries.first?.result == nil)
        #expect(try journal.snapshot().after == .zero)
    }
}

private actor AccountSyncScriptedTransport: AccountSyncTransport {
    private let result: AccountSyncMutationResult
    private var pages: [AccountSyncChangePage]
    private(set) var requests: [AccountSyncChangesRequest] = []

    init(result: AccountSyncMutationResult, pages: [AccountSyncChangePage]) {
        self.result = result; self.pages = pages
    }
    func mutate(_ mutation: AccountSyncMutation, accessToken: String) async throws -> AccountSyncMutationResult { result }
    func changes(_ request: AccountSyncChangesRequest, accessToken: String) async throws -> AccountSyncChangePage {
        requests.append(request)
        guard !pages.isEmpty else { throw AccountSyncError.invalidWire }
        return pages.removeFirst()
    }
}

private actor AccountSyncSuspendedTransport: AccountSyncTransport {
    private var reply: CheckedContinuation<AccountSyncMutationResult, Never>?
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?

    func mutate(_ mutation: AccountSyncMutation, accessToken: String) async throws -> AccountSyncMutationResult {
        await withCheckedContinuation { continuation in
            reply = continuation
            started = true
            waiter?.resume(); waiter = nil
        }
    }
    func changes(_ request: AccountSyncChangesRequest, accessToken: String) async throws -> AccountSyncChangePage {
        throw AccountSyncError.staleOperation
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func complete(_ result: AccountSyncMutationResult) {
        reply?.resume(returning: result); reply = nil
    }
}