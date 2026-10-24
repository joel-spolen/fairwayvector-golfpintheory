import Combine
import Foundation
import SwiftData

/// One session owner for all windows. Account content is never opened before auth.
@MainActor
final class PinTheoryAccountSession: ObservableObject {
    let auth: PinTheoryAuthService?
    let browser = PinTheoryWebAuthenticationBroker()
    @Published private(set) var accountData: PinTheoryAccountData?
    @Published private(set) var accountDetails: PinTheoryAccountDetails?
    @Published private(set) var message: String?
    @Published private(set) var accountDeletionNotice: String?
    @Published private(set) var isSyncingSavedData = false
    @Published private(set) var savedDataSyncMessage: String?
    @Published private(set) var savedDataSyncConflictCount = 0
    @Published private(set) var started = false
    private let projectHost: String?
    private var subscription: AnyCancellable?
    private var restoreTask: Task<Void, Never>?
    private var pendingCallback: URL?
    private var busySubscription: AnyCancellable?
    private var activeSyncCoordinator: AccountSyncCoordinator?
    private var syncRequestedWhileBusy = false

    private static let syncOptInKey = "accountSync.savedRecordsOptIn.v1"

    var hasOptedIntoSavedDataSync: Bool {
        guard let defaults = accountData?.defaults else { return false }
        return defaults.object(forKey: Self.syncOptInKey) as? Bool ?? true
    }

    func setSavedDataSyncEnabled(_ enabled: Bool, roundStore: PlayedRoundStore,
                                 profile: PlayerProfile?, modelContext: ModelContext) {
        guard let defaults = accountData?.defaults else { return }
        defaults.set(enabled, forKey: Self.syncOptInKey)
        guard enabled else {
            if let activeSyncCoordinator {
                Task { await activeSyncCoordinator.invalidate() }
                self.activeSyncCoordinator = nil
            }
            savedDataSyncMessage = "Cloud sync is off. Saved data remains on this device."
            return
        }
        Task { await enableAndSyncSavedData(roundStore: roundStore, profile: profile, modelContext: modelContext) }
    }

    init() {
        do {
            guard let configuration = try PinTheoryAuthConfiguration.load() else {
                auth = nil; projectHost = nil
                message = "Account sign-in is not configured in this build."
                return
            }
            projectHost = configuration.projectURL.host
            let service = PinTheoryAuthService(configuration: configuration)
            auth = service
            subscription = service.$state.sink { [weak self] state in self?.apply(state) }
            busySubscription = service.$isBusy.sink { [weak self] busy in
                guard !busy else { return }
                Task { @MainActor [weak self] in await self?.processPendingCallback() }
            }
        } catch {
            auth = nil; projectHost = nil
            message = "Account configuration is unavailable. Please contact the developer."
        }
    }

    func start() {
        guard !started else { return }
        started = true
        restore()
    }

    func restore() {
        guard let auth, !auth.isBusy else { return }
        restoreTask?.cancel()
        restoreTask = Task { @MainActor in
            do { try await auth.restore() }
            catch { /* The service publishes a sanitized error and locks on storage failure. */ }
        }
    }

    func openAccountAgain() {
        guard let auth else { return }
        apply(auth.state)
    }

    func retrySecureStorage() async {
        message = nil
        do { try await auth?.retrySecureStorage() }
        catch { /* Sanitized service error drives recovery UI. */ }
    }

    func handle(_ url: URL) async {
        guard PinTheoryAuthConfiguration.acceptsCallback(url), auth != nil else { return }
        // Google callbacks are consumed directly by ASWebAuthenticationSession.
        guard !browser.isAuthenticating else { return }
        pendingCallback = url
        if !started { start() }
        await processPendingCallback()
    }

    private func processPendingCallback() async {
        // A cold-start link must wait until restoration has examined Keychain.
        await restoreTask?.value
        guard let auth, !auth.isBusy, let url = pendingCallback else { return }
        pendingCallback = nil
        if PinTheoryAuthConfiguration.isPasswordResetCallback(url) {
            // Recovery must detach any open account, including in other windows.
            accountData = nil
        } else {
            guard auth.state == .signedOut || auth.state == .passwordRecovery else { return }
        }
        do { try await auth.handleCallback(url) }
        catch { /* Never display callback URLs or raw server errors. */ }
    }

    func signOut() {
        pendingCallback = nil
        browser.cancel()
        restoreTask?.cancel()
        if let activeSyncCoordinator {
            Task { await activeSyncCoordinator.invalidate() }
            self.activeSyncCoordinator = nil
        }
        isSyncingSavedData = false
        accountData = nil
        accountDetails = nil
        message = nil
        do { try auth?.signOut() }
        catch { message = "Secure sign-out could not finish. Please retry before using another account." }
    }

    func deleteAccount() async throws {
        guard let auth else { throw PinTheoryAuthError.authenticationRequired }
        accountDeletionNotice = nil
        let existingData = accountData
        do { try await auth.deleteAccount() }
        catch {
            // The server may have confirmed deletion even if local Keychain cleanup failed.
            // Continue to the signed-out UI only for that confirmed-success state.
            guard auth.accountWasDeleted else { throw error }
        }
        // Backend deletion succeeded. Never restore this identity locally even if
        // device cleanup reports an error; surface that partial-cleanup result.
        accountData = nil
        var localCleanupFailed = false
        if let existingData {
            do { try existingData.eraseLocalContent() }
            catch { localCleanupFailed = true }
        }
        accountDeletionNotice = localCleanupFailed
            ? "Your account was deleted, but some records remain on this device. Remove Golf PinTheory from this device or contact support."
            : "Your Golf PinTheory account was deleted."
    }

    func loadAccountDetails() async throws -> PinTheoryAccountDetails {
        guard let accountData else { throw PinTheoryAuthError.authenticationRequired }
        // Display cached account details immediately, then refresh them from Auth.
        if accountDetails == nil { accountDetails = accountData.loadAccountProfile() }
        if let cached = accountDetails, accountData.accountProfileCacheIsFresh() { return cached }
        guard let auth else { throw PinTheoryAuthError.authenticationRequired }
        guard case .authenticated = auth.state else {
            if let cached = accountDetails { return cached }
            throw PinTheoryAuthError.authenticationRequired
        }
        do {
            let verified = try await auth.accountDetails()
            try accountData.saveAccountProfile(verified)
            accountDetails = verified
            return verified
        } catch {
            if let cached = accountDetails { return cached }
            throw error
        }
    }

    func updateAccountDisplayName(firstName: String, lastName: String) async throws -> PinTheoryAccountDetails {
        guard let auth, let accountData else { throw PinTheoryAuthError.authenticationRequired }
        let updated = try await auth.updateDisplayName(firstName: firstName, lastName: lastName)
        try accountData.saveAccountProfile(updated)
        accountDetails = updated
        return updated
    }

    /// Account-scoped sync for approved saved data. Enabled by default unless the
    /// user turns it off in Settings. Active drafts, preferences, catalogs and geometry stay local.
    func enableAndSyncSavedData(roundStore: PlayedRoundStore, profile: PlayerProfile?,
                                modelContext: ModelContext) async {
        guard let accountData, let auth else { return }
        if isSyncingSavedData {
            syncRequestedWhileBusy = true
            return
        }
        let wasAlreadyOptedIn = hasOptedIntoSavedDataSync
        isSyncingSavedData = true
        accountData.defaults.set(true, forKey: Self.syncOptInKey)
        savedDataSyncMessage = "Preparing secure sync…"
        defer {
            isSyncingSavedData = false
            activeSyncCoordinator = nil
            if syncRequestedWhileBusy {
                syncRequestedWhileBusy = false
                Task { @MainActor [weak self] in
                    await self?.enableAndSyncSavedData(roundStore: roundStore, profile: profile,
                                                       modelContext: modelContext)
                }
            }
        }

        do {
            guard case .authenticated(let identity) = auth.state,
                  accountData.id.hasSuffix(identity.userID.uuidString.lowercased()) else {
                throw AccountSyncError.authenticationRequired
            }
            let configuration = try auth.accountSyncConfiguration()
            let journal = try AccountSyncJournal(ownerID: identity.userID,
                root: accountData.directory.appendingPathComponent("CloudSync", isDirectory: true))
            let transport = URLSessionAccountSyncTransport(configuration: configuration)
            let coordinator = AccountSyncCoordinator(journal: journal, transport: transport)
            activeSyncCoordinator = coordinator

            // Capture the last common snapshot, then pull first. This prevents a
            // fresh device's default profile or same-ID local records from blindly
            // replacing existing cloud data during first-device bootstrap.
            let lastKnown = try journal.snapshot()
            savedDataSyncMessage = "Checking saved data in the cloud…"
            let accessToken = try await auth.authenticatedAccessToken(for: identity.userID)
            // Refuse all sync traffic until the strict payload allowlist migration
            // is installed. Older foundation-only deployments accept generic JSON.
            try await transport.validateServerContract(accessToken: accessToken)
            try Task.checkCancellation()
            guard case .authenticated(let validatedIdentity) = auth.state,
                validatedIdentity.userID == identity.userID else { throw AccountSyncError.staleOperation }
            _ = try await coordinator.synchronize(ownerID: identity.userID, accessToken: accessToken)
            try Task.checkCancellation()
            guard case .authenticated(let afterPullIdentity) = auth.state,
                afterPullIdentity.userID == identity.userID else { throw AccountSyncError.staleOperation }
            let baseline = try journal.snapshot()
            let conflicts = Set(baseline.conflicts.map { $0.local.recordID })
            let pendingByRecord = Dictionary(grouping: baseline.pending, by: \.recordID)
            var queuedIDs = Set(baseline.pending.map(\.recordID))
            var queued = 0
            var locallyResolvedDeletions = Set<UUID>()

            func enqueue(_ mutation: AccountSyncMutation, payload: [String: JSONValue]) throws {
                if conflicts.contains(mutation.recordID) { return }
                if let pending = pendingByRecord[mutation.recordID] {
                    // Never replace or discard an earlier durable mutation. Its exact
                    // request is replayed first; a newer local edit queues next time.
                    if pending.contains(where: { $0.kind == mutation.kind && $0.payload == payload }) { return }
                    return
                }
                guard !queuedIDs.contains(mutation.recordID) else { return }
                let server = baseline.serverRecords.first { $0.recordID == mutation.recordID }
                if let server, server.deletedAt == nil, server.payload == payload { return }
                let oldServer = lastKnown.serverRecords.first { $0.recordID == mutation.recordID }
                let oldLocal = lastKnown.localRecords.first { $0.recordID == mutation.recordID }
                let hadMatchingBase = oldServer != nil && oldServer?.deletedAt == nil
                    && oldLocal == oldServer.map(AccountSyncLocalRecord.init(record:))
                let wasPendingBeforePull = lastKnown.pending.contains { $0.recordID == mutation.recordID }
                let expected = hadMatchingBase
                    ? (wasPendingBeforePull ? (server?.revision ?? .zero) : (oldServer?.revision ?? .zero))
                    : (mutation.operation == .delete && wasPendingBeforePull ? (server?.revision ?? .zero) : .zero)
                let prepared = try AccountSyncMutation(mutationID: mutation.mutationID,
                    recordID: mutation.recordID, kind: mutation.kind, expectedRevision: expected,
                    operation: mutation.operation, schemaVersion: mutation.schemaVersion, payload: mutation.payload)
                try journal.enqueue(prepared)
                queuedIDs.insert(mutation.recordID)
                queued += 1
            }

            // First sync merges this device's saved scorecards into the account.
            // On a fresh device this list is empty and cloud data is pulled.
            for round in roundStore.saved {
                let template = try AccountSyncDomainAdapter.playedRoundMutation(round, expectedRevision: .zero)
                try enqueue(template, payload: template.payload)
            }

            let clubs = try modelContext.fetch(FetchDescriptor<GolfClub>())
            let courses = try modelContext.fetch(FetchDescriptor<GolfCourse>())
            let tees = try modelContext.fetch(FetchDescriptor<TeeSet>())
            let customRecords = try AccountSyncDomainAdapter.customMutations(ownerID: identity.userID,
                clubs: clubs, courses: courses, tees: tees)
            let handicapRounds = try modelContext.fetch(FetchDescriptor<GolfRound>())
            for round in handicapRounds where round.syncID == nil {
                _ = AccountSyncDomainAdapter.handicapRoundRecordID(round)
            }
            try modelContext.save()
            for mutation in customRecords.mutations {
                try enqueue(mutation, payload: mutation.payload)
            }

            let storedWedgeSetup = accountData.defaults.string(forKey: "wedgeMatrix.wedges") ?? ""
            let hasStoredWedgeSetup = !storedWedgeSetup.isEmpty
            let localWedges = hasStoredWedgeSetup ? Wedge.catalog(from: storedWedgeSetup) : []
            var localWedgeIDs = Set<UUID>()
            for wedge in localWedges {
                let mutation = try AccountSyncDomainAdapter.wedgeMutation(wedge, ownerID: identity.userID)
                localWedgeIDs.insert(mutation.recordID)
                try enqueue(mutation, payload: mutation.payload)
            }

            var localHandicapIDs = Set<UUID>()
            for round in handicapRounds {
                let mutation = try AccountSyncDomainAdapter.handicapRoundMutation(round)
                localHandicapIDs.insert(mutation.recordID)
                try enqueue(mutation, payload: mutation.payload)
            }

            // After opt-in, a formerly synchronized local item missing from its
            // source store is an explicit deletion. On first opt-in, absence is
            // never interpreted as consent to delete remote records.
            func deletionPriority(_ kind: AccountSyncRecordKind) -> Int {
                switch kind {
                case .customTee: 0
                case .customCourse: 1
                case .customClub: 2
                default: 3
                }
            }
            if wasAlreadyOptedIn {
                let currentIDs = Set(customRecords.mutations.map(\.recordID))
                    .union(hasStoredWedgeSetup ? localWedgeIDs : []).union(localHandicapIDs)
                let deletions = lastKnown.localRecords.filter { prior in
                    !prior.isDeleted
                        && [.customClub, .customCourse, .customTee, .wedge, .handicapRound].contains(prior.kind)
                        && (prior.kind != .wedge || hasStoredWedgeSetup)
                        && !currentIDs.contains(prior.recordID)
                }.sorted { deletionPriority($0.kind) < deletionPriority($1.kind) }
                for prior in deletions {
                    let deletion = try AccountSyncMutation(recordID: prior.recordID, kind: prior.kind,
                        expectedRevision: .zero, operation: .delete, payload: [:])
                    try enqueue(deletion, payload: [:])
                }
            }

            for deletedID in roundStore.pendingCloudDeletions {
                guard !conflicts.contains(deletedID), pendingByRecord[deletedID] == nil else { continue }
                guard let server = baseline.serverRecords.first(where: { $0.recordID == deletedID }) else {
                    locallyResolvedDeletions.insert(deletedID)
                    continue
                }
                if server.deletedAt != nil {
                    locallyResolvedDeletions.insert(deletedID)
                    continue
                }
                let oldServer = lastKnown.serverRecords.first { $0.recordID == deletedID }
                let oldLocal = lastKnown.localRecords.first { $0.recordID == deletedID }
                let knownBase = oldServer != nil && oldServer?.deletedAt == nil
                    && oldLocal == oldServer.map(AccountSyncLocalRecord.init(record:))
                let wasPendingBeforePull = lastKnown.pending.contains { $0.recordID == deletedID }
                let deletion = try AccountSyncMutation(recordID: deletedID, kind: .playedRound,
                    expectedRevision: knownBase
                        ? (wasPendingBeforePull ? server.revision : (oldServer?.revision ?? .zero))
                        : (wasPendingBeforePull ? server.revision : .zero),
                    operation: .delete, payload: [:])
                try journal.enqueue(deletion)
                queued += 1
            }

            let profileID = AccountSyncDomainAdapter.golferProfileRecordID(ownerID: identity.userID)
            if let profile {
                let hasPersonalFacts = profile.name != "Player" || profile.lowHandicapIndex != nil
                if hasPersonalFacts {
                    let profileMutation = try AccountSyncDomainAdapter.golferProfileMutation(profile,
                        ownerID: identity.userID, expectedRevision: .zero)
                    try enqueue(profileMutation, payload: profileMutation.payload)
                }
            }

            accountData.defaults.set(true, forKey: Self.syncOptInKey)
            savedDataSyncMessage = queued > 0 || !baseline.pending.isEmpty
                ? "Syncing saved records…" : "Checking for cloud updates…"
            _ = try await coordinator.synchronize(ownerID: identity.userID, accessToken: accessToken)
            try Task.checkCancellation()
            guard case .authenticated(let current) = auth.state, current.userID == identity.userID,
                  accountData.id.hasSuffix(identity.userID.uuidString.lowercased()) else {
                throw AccountSyncError.staleOperation
            }

            // Local edits made while the first push was in flight must not be
            // replaced by that older acknowledged snapshot. Queue the newer local
            // snapshot against the now-current server revision before applying it.
            let reconciled = try journal.snapshot()
            let reconciledConflicts = Set(reconciled.conflicts.map { $0.local.recordID })
            var followUpQueued = false
            for round in roundStore.saved {
                let template = try AccountSyncDomainAdapter.playedRoundMutation(round, expectedRevision: .zero)
                guard !reconciledConflicts.contains(round.id),
                      !reconciled.pending.contains(where: { $0.recordID == round.id }) else { continue }
                guard let server = reconciled.serverRecords.first(where: { $0.recordID == round.id }),
                      server.deletedAt == nil, server.payload != template.payload else { continue }
                let update = try AccountSyncMutation(recordID: round.id, kind: .playedRound,
                    expectedRevision: server.revision, payload: template.payload)
                try journal.enqueue(update)
                followUpQueued = true
            }
            for deletedID in roundStore.pendingCloudDeletions {
                guard !reconciledConflicts.contains(deletedID),
                      !reconciled.pending.contains(where: { $0.recordID == deletedID }),
                      let server = reconciled.serverRecords.first(where: { $0.recordID == deletedID }),
                      server.deletedAt == nil else { continue }
                let deletion = try AccountSyncMutation(recordID: deletedID, kind: .playedRound,
                    expectedRevision: server.revision, operation: .delete, payload: [:])
                try journal.enqueue(deletion)
                followUpQueued = true
            }

            let currentProfileID = AccountSyncDomainAdapter.golferProfileRecordID(ownerID: identity.userID)
            if let profile, !reconciledConflicts.contains(currentProfileID),
               !reconciled.pending.contains(where: { $0.recordID == currentProfileID }),
               let server = reconciled.serverRecords.first(where: { $0.recordID == currentProfileID }),
               server.deletedAt == nil {
                let latestProfile = try AccountSyncDomainAdapter.golferProfileMutation(profile,
                    ownerID: identity.userID, expectedRevision: .zero)
                if server.payload != latestProfile.payload {
                    let update = try AccountSyncMutation(recordID: currentProfileID, kind: .golferProfile,
                        expectedRevision: server.revision, payload: latestProfile.payload)
                    try journal.enqueue(update)
                    followUpQueued = true
                }
            }
            if followUpQueued {
                savedDataSyncMessage = "Syncing your latest changes…"
                _ = try await coordinator.synchronize(ownerID: identity.userID, accessToken: accessToken)
                try Task.checkCancellation()
                guard case .authenticated(let latestIdentity) = auth.state,
                      latestIdentity.userID == identity.userID else { throw AccountSyncError.staleOperation }
            }

            // Reconcile newly discovered local deletions and local edits for the
            // expanded record kinds against their pulled server revisions.
            let latestSnapshot = try journal.snapshot()
            let latestConflicts = Set(latestSnapshot.conflicts.map { $0.local.recordID })
            let latestPendingIDs = Set(latestSnapshot.pending.map(\.recordID))
            var domainFollowUpQueued = false

            func enqueueDomainUpdate(_ mutation: AccountSyncMutation) throws {
                guard !latestConflicts.contains(mutation.recordID),
                      !latestPendingIDs.contains(mutation.recordID),
                      let server = latestSnapshot.serverRecords.first(where: { $0.recordID == mutation.recordID }),
                      server.deletedAt == nil, server.payload != mutation.payload else { return }
                let update = try AccountSyncMutation(recordID: mutation.recordID, kind: mutation.kind,
                    expectedRevision: server.revision, operation: mutation.operation, payload: mutation.payload)
                try journal.enqueue(update)
                domainFollowUpQueued = true
            }

            for mutation in customRecords.mutations { try enqueueDomainUpdate(mutation) }
            let latestStoredWedgeSetup = accountData.defaults.string(forKey: "wedgeMatrix.wedges") ?? ""
            let hasLatestWedgeSetup = !latestStoredWedgeSetup.isEmpty
            for wedge in (hasLatestWedgeSetup ? Wedge.catalog(from: latestStoredWedgeSetup) : []) {
                try enqueueDomainUpdate(AccountSyncDomainAdapter.wedgeMutation(wedge, ownerID: identity.userID))
            }
            for round in handicapRounds {
                try enqueueDomainUpdate(AccountSyncDomainAdapter.handicapRoundMutation(round))
            }
            if wasAlreadyOptedIn {
                let currentDomainIDs = Set(customRecords.mutations.map(\.recordID))
                    .union(hasLatestWedgeSetup ? Set(Wedge.catalog(from: latestStoredWedgeSetup).map {
                        AccountSyncDomainAdapter.wedgeRecordID(ownerID: identity.userID, wedgeName: $0.name)
                    }) : []).union(localHandicapIDs)
                let deletions = latestSnapshot.localRecords.filter { prior in
                    !prior.isDeleted
                        && [.customClub, .customCourse, .customTee, .wedge, .handicapRound].contains(prior.kind)
                        && (prior.kind != .wedge || hasLatestWedgeSetup)
                        && !currentDomainIDs.contains(prior.recordID)
                        && !latestConflicts.contains(prior.recordID) && !latestPendingIDs.contains(prior.recordID)
                }.sorted { deletionPriority($0.kind) < deletionPriority($1.kind) }
                for prior in deletions {
                    guard let server = latestSnapshot.serverRecords.first(where: { $0.recordID == prior.recordID }),
                          server.deletedAt == nil else { continue }
                    let deletion = try AccountSyncMutation(recordID: prior.recordID, kind: prior.kind,
                        expectedRevision: server.revision, operation: .delete, payload: [:])
                    try journal.enqueue(deletion)
                    domainFollowUpQueued = true
                }
            }
            if domainFollowUpQueued {
                savedDataSyncMessage = "Syncing your latest changes…"
                _ = try await coordinator.synchronize(ownerID: identity.userID, accessToken: accessToken)
                try Task.checkCancellation()
                guard case .authenticated(let latestIdentity) = auth.state,
                      latestIdentity.userID == identity.userID else { throw AccountSyncError.staleOperation }
            }

            try Task.checkCancellation()
            guard case .authenticated(let completedIdentity) = auth.state,
                completedIdentity.userID == identity.userID else { throw AccountSyncError.staleOperation }

            let final = try journal.snapshot()
            let finalConflicts = Set(final.conflicts.map { $0.local.recordID })
            let roundRecords = final.localRecords.filter { $0.kind == .playedRound }
            let remoteRounds = try roundRecords.filter { !$0.isDeleted && !finalConflicts.contains($0.recordID) }
                .map(AccountSyncDomainAdapter.playedRound(from:))
            let cloudDeletedRounds = Set(roundRecords.filter(\.isDeleted).map(\.recordID))
            let appliedDeletions = Set(final.entries.compactMap { entry -> UUID? in
                guard entry.mutation.kind == .playedRound, entry.mutation.operation == .delete,
                      case .applied = entry.result else { return nil }
                return entry.mutation.recordID
            })
            try roundStore.mergeCloudRecords(remoteRounds, deletedIDs: cloudDeletedRounds,
                                             acknowledgedDeletionIDs: appliedDeletions.union(locallyResolvedDeletions))

            try applyCloudCustomRecords(final.localRecords, conflicts: finalConflicts,
                                        ownerID: identity.userID, modelContext: modelContext)
            try applyCloudWedgeRecords(final.localRecords, conflicts: finalConflicts,
                                       ownerID: identity.userID, defaults: accountData.defaults)
            try applyCloudHandicapRounds(final.localRecords, conflicts: finalConflicts, modelContext: modelContext)

            if let profileRecord = final.localRecords.first(where: {
                $0.recordID == profileID && $0.kind == .golferProfile && !$0.isDeleted
                    && !finalConflicts.contains($0.recordID)
            }) {
                let synced = try AccountSyncDomainAdapter.golferProfile(from: profileRecord)
                if let profile {
                    profile.name = synced.name
                    profile.lowHandicapIndex = synced.lowHandicapIndex
                } else {
                    modelContext.insert(PlayerProfile(name: synced.name, lowHandicapIndex: synced.lowHandicapIndex))
                }
                try modelContext.save()
            }

            savedDataSyncConflictCount = final.conflicts.count
            if !final.conflicts.isEmpty {
                savedDataSyncMessage = "Sync completed with \(final.conflicts.count) conflict(s). Both versions are preserved; resolve these before retrying sync."
            } else if !final.pending.isEmpty {
                savedDataSyncMessage = "Sync is incomplete: \(final.pending.count) saved change(s) remain queued. Tap Sync now to retry."
            } else {
                savedDataSyncMessage = "Cloud sync complete. \(roundStore.saved.count) saved scorecards are available on this device."
            }
        } catch {
            savedDataSyncMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyCloudCustomRecords(_ records: [AccountSyncLocalRecord], conflicts: Set<UUID>,
                                         ownerID: UUID, modelContext: ModelContext) throws {
        let relevant = records.filter { [.customClub, .customCourse, .customTee].contains($0.kind) }
        guard !relevant.isEmpty else { return }
        let clubs = try modelContext.fetch(FetchDescriptor<GolfClub>())
        let courses = try modelContext.fetch(FetchDescriptor<GolfCourse>())
        let tees = try modelContext.fetch(FetchDescriptor<TeeSet>())

        // Delete dependents before their parent; every incoming upsert below is
        // account-scoped and only creates records marked custom.
        for record in relevant where !conflicts.contains(record.recordID) && record.isDeleted {
            switch record.kind {
            case .customTee:
                for tee in tees where tee.syncID == record.recordID { modelContext.delete(tee) }
            case .customCourse:
                if let course = courses.first(where: { $0.syncID == record.recordID }) {
                    for tee in tees where tee.isCustom == true && tee.clubName == course.clubName
                        && tee.courseName == course.name { modelContext.delete(tee) }
                }
                for course in courses where course.syncID == record.recordID { modelContext.delete(course) }
            case .customClub:
                if let club = clubs.first(where: { $0.syncID == record.recordID }) {
                    for tee in tees where tee.isCustom == true && tee.clubName == club.name { modelContext.delete(tee) }
                    for course in courses where course.isCustom == true && course.clubName == club.name { modelContext.delete(course) }
                }
                for club in clubs where club.syncID == record.recordID { modelContext.delete(club) }
            default: break
            }
        }

        for record in relevant where !conflicts.contains(record.recordID) && !record.isDeleted && record.kind == .customClub {
            let value = try AccountSyncDomainAdapter.customClub(from: record)
            let club = clubs.first(where: { $0.syncID == value.id })
                ?? GolfClub(name: value.name, city: value.city, country: value.country, isCustom: true)
            club.syncID = value.id
            club.name = value.name; club.city = value.city; club.country = value.country; club.isCustom = true
            if club.modelContext == nil { modelContext.insert(club) }
        }
        for record in relevant where !conflicts.contains(record.recordID) && !record.isDeleted && record.kind == .customCourse {
            let value = try AccountSyncDomainAdapter.customCourse(from: record)
            let clubName = clubs.first(where: { $0.syncID == value.clubID })?.name ?? value.clubName
            let course = courses.first(where: { $0.syncID == value.id })
                ?? GolfCourse(clubName: clubName, name: value.name, isCustom: true)
            course.syncID = value.id; course.clubName = clubName; course.name = value.name; course.isCustom = true
            if course.modelContext == nil { modelContext.insert(course) }
        }
        for record in relevant where !conflicts.contains(record.recordID) && !record.isDeleted && record.kind == .customTee {
            let value = try AccountSyncDomainAdapter.customTee(from: record)
            let data = value.payload
            let clubName = clubs.first(where: { $0.syncID == value.clubID })?.name ?? data.clubName
            let courseName = courses.first(where: { $0.syncID == value.courseID })?.name ?? data.courseName
            let tee = tees.first(where: { $0.syncID == value.id }) ?? TeeSet(clubName: clubName,
                courseName: courseName, name: data.name, holes: data.holes, par: data.par,
                courseRating: data.courseRating, slopeRating: data.slopeRating,
                ratingSexRawValue: data.ratingSex, isCustom: true,
                holeParsData: data.holePars, holeHandicapIndicesData: data.holeHandicapIndices)
            tee.syncID = value.id; tee.clubName = clubName; tee.courseName = courseName; tee.name = data.name
            tee.holes = data.holes; tee.par = data.par; tee.courseRating = data.courseRating
            tee.slopeRating = data.slopeRating; tee.ratingSexRawValue = data.ratingSex; tee.isCustom = true
            tee.holeParsData = data.holePars; tee.holeHandicapIndicesData = data.holeHandicapIndices
            if tee.modelContext == nil { modelContext.insert(tee) }
        }
        try modelContext.save()
    }

    @MainActor
    private func applyCloudWedgeRecords(_ records: [AccountSyncLocalRecord], conflicts: Set<UUID>,
                                        ownerID: UUID, defaults: UserDefaults) throws {
        let wedgeRecords = records.filter { $0.kind == .wedge && !conflicts.contains($0.recordID) }
        guard !wedgeRecords.isEmpty else { return }
        var wedges = Wedge.catalog(from: defaults.string(forKey: "wedgeMatrix.wedges") ?? "")
        for record in wedgeRecords {
            if record.isDeleted {
                wedges.removeAll { AccountSyncDomainAdapter.wedgeRecordID(ownerID: ownerID, wedgeName: $0.name) == record.recordID }
                continue
            }
            let remote = try AccountSyncDomainAdapter.wedge(from: record, ownerID: ownerID)
            if let index = wedges.firstIndex(where: {
                AccountSyncDomainAdapter.wedgeRecordID(ownerID: ownerID, wedgeName: $0.name) == record.recordID
            }) {
                wedges[index] = remote
            } else {
                wedges.append(remote)
            }
        }
        do {
            let data = try JSONEncoder().encode(wedges)
            defaults.set(String(decoding: data, as: UTF8.self), forKey: "wedgeMatrix.wedges")
            guard defaults.synchronize() else { throw AccountSyncError.storageUnavailable }
        } catch let error as AccountSyncError { throw error }
        catch { throw AccountSyncError.storageUnavailable }
    }

    @MainActor
    private func applyCloudHandicapRounds(_ records: [AccountSyncLocalRecord], conflicts: Set<UUID>,
                                          modelContext: ModelContext) throws {
        let roundRecords = records.filter { $0.kind == .handicapRound && !conflicts.contains($0.recordID) }
        guard !roundRecords.isEmpty else { return }
        let rounds = try modelContext.fetch(FetchDescriptor<GolfRound>())
        for record in roundRecords {
            if record.isDeleted {
                for round in rounds where round.syncID == record.recordID { modelContext.delete(round) }
                continue
            }
            let value = try AccountSyncDomainAdapter.handicapRound(from: record)
            let round = rounds.first(where: { $0.syncID == value.id }) ?? GolfRound(
                date: value.payload.date, clubName: value.payload.clubName, courseName: value.payload.courseName,
                teeName: value.payload.teeName, holes: value.payload.holes, inputMode: value.payload.inputMode,
                adjustedGrossScore: value.payload.adjustedGrossScore, stablefordPoints: value.payload.stablefordPoints,
                handicapDifferential: value.payload.handicapDifferential, par: value.payload.par,
                courseRating: value.payload.courseRating, slopeRating: value.payload.slopeRating, pcc: value.payload.pcc,
                notes: value.payload.notes, holeScoresData: value.payload.holeScores,
                holeParsData: value.payload.holePars, holeHandicapIndicesData: value.payload.holeHandicapIndices)
            round.syncID = value.id
            round.date = value.payload.date; round.clubName = value.payload.clubName
            round.courseName = value.payload.courseName; round.teeName = value.payload.teeName
            round.holes = value.payload.holes; round.inputModeRawValue = value.payload.inputMode.rawValue
            round.adjustedGrossScore = value.payload.adjustedGrossScore; round.stablefordPoints = value.payload.stablefordPoints
            round.handicapDifferential = value.payload.handicapDifferential; round.par = value.payload.par
            round.courseRating = value.payload.courseRating; round.slopeRating = value.payload.slopeRating
            round.pcc = value.payload.pcc; round.notes = value.payload.notes
            round.holeScoresData = value.payload.holeScores; round.holeParsData = value.payload.holePars
            round.holeHandicapIndicesData = value.payload.holeHandicapIndices
            round.sourceSavedRoundID = value.payload.sourceSavedRoundID
            if round.modelContext == nil { modelContext.insert(round) }
        }
        try modelContext.save()
    }

    private func apply(_ state: PinTheoryAuthState) {
        switch state {
        case .authenticated(let identity), .offlineCachedIdentity(let identity):
            if auth?.accountWasDeleted != true { accountDeletionNotice = nil }
            guard let projectHost else { return }
            do {
                if accountData?.id.hasSuffix(identity.userID.uuidString.lowercased()) == true { return }
                accountData = nil
                accountData = try PinTheoryAccountData(projectHost: projectHost, userID: identity.userID)
                if accountData?.defaults.object(forKey: Self.syncOptInKey) == nil {
                    accountData?.defaults.set(true, forKey: Self.syncOptInKey)
                }
                accountDetails = accountData?.loadAccountProfile()
                message = nil
            } catch {
                accountData = nil
                message = "Your account storage could not be opened. Existing records have been preserved. Retry or sign out."
            }
        case .signedOut, .restoring, .passwordRecovery:
            if let activeSyncCoordinator {
                Task { await activeSyncCoordinator.invalidate() }
                self.activeSyncCoordinator = nil
            }
            syncRequestedWhileBusy = false
            isSyncingSavedData = false
            accountData = nil
            accountDetails = nil
                if message?.hasPrefix("Your Golf PinTheory account was deleted") != true,
                    message?.hasPrefix("Your account was deleted") != true {
                message = nil
            }
        }
    }
}