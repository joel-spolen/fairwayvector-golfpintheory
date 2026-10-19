import Foundation

nonisolated struct AccountSyncRunSummary: Sendable, Equatable {
    let pushed: Int
    let pagesApplied: Int
    let finishedPullWindow: Bool
    let pendingCount: Int
    let conflictCount: Int
    let durableAfter: AccountSyncRevision
}

/// Explicit, bounded foreground work only. This is NOT an app sync engine or auth
/// lifecycle. Create one coordinator per authenticated account lifetime; invalidate
/// on logout/account change, discard it, then create a new account-bound instance.
actor AccountSyncCoordinator {
    nonisolated let ownerID: UUID
    private let journal: AccountSyncJournal
    private let transport: any AccountSyncTransport
    private var generation: UInt64 = 0
    private var invalidated = false
    private var running = false

    init(journal: AccountSyncJournal, transport: any AccountSyncTransport) {
        ownerID = journal.ownerID
        self.journal = journal
        self.transport = transport
    }

    /// Late responses cannot commit after this returns. An already-sent RPC may
    /// still commit server-side; its ORIGINAL mutation stays pending for safe replay.
    func invalidate() {
        invalidated = true
        generation &+= 1
    }

    /// Caller must verify the token belongs to ownerID. No token is retained as a
    /// property or journal field. Refresh/auth/gating belongs to a later integration.
    /// If a limit is reached, call again: persisted pending IDs/window cursor resume.
    func synchronize(ownerID requestedOwner: UUID, accessToken: String,
                     mutationLimit: Int = 100, pageLimit: Int = 20, pageSize: Int = 100) async throws -> AccountSyncRunSummary {
        guard requestedOwner == ownerID, !invalidated else { throw AccountSyncError.staleOperation }
        guard !running else { throw AccountSyncError.recordBusy }
        guard (1...200).contains(mutationLimit), (1...200).contains(pageLimit), (1...200).contains(pageSize) else {
            throw AccountSyncError.invalidWire
        }
        running = true
        defer { running = false }
        let captured = generation
        var pushed = 0
        var pages = 0
        var finished = false
        // Freeze this run's outbox. New local edits wait for the next explicit run.
        let pending = try journal.snapshot().pending.prefix(mutationLimit)
        for mutation in pending {
            try check(captured)
            let result: AccountSyncMutationResult
            do { result = try await transport.mutate(mutation, accessToken: accessToken) }
            catch { try check(captured); throw sanitized(error) }
            try check(captured)
            // Synchronous locked journal transaction: no actor reentrancy between
            // generation check and durable commit.
            try journal.acknowledge(result)
            pushed += 1
        }
        for _ in 0..<pageLimit {
            try check(captured)
            let request = try journal.changesRequest(limit: pageSize)
            let page: AccountSyncChangePage
            do { page = try await transport.changes(request, accessToken: accessToken) }
            catch { try check(captured); throw sanitized(error) }
            try check(captured)
            try journal.apply(page, for: request)
            pages += 1
            if !page.hasMore { finished = true; break }
        }
        let state = try journal.snapshot()
        return AccountSyncRunSummary(pushed: pushed, pagesApplied: pages, finishedPullWindow: finished,
            pendingCount: state.pending.count, conflictCount: state.conflicts.count, durableAfter: state.after)
    }

    private func check(_ captured: UInt64) throws {
        guard !Task.isCancelled, !invalidated, captured == generation else { throw AccountSyncError.staleOperation }
    }

    private func sanitized(_ error: any Error) -> AccountSyncError {
        (error as? AccountSyncError) ?? .transportUnavailable
    }
}