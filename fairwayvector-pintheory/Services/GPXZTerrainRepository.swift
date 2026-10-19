import Foundation
import CryptoKit

nonisolated struct TerrainQuota: Sendable {
    let used: Int
    let month: String
    var remaining: Int { max(0, 100 - used) }
}

/// One persistent account-scope LOCAL safety ledger, shared by every course/store.
/// It is not account-wide authority across devices, other apps, reinstalls, or restored backups.
actor GPXZBudgetLedger {
    struct Ledger: Codable, Sendable {
        var schemaVersion = 1
        var months: [String: Int] = [:]
        var retryNotBefore: Date?
        // Optional for compatibility with existing ledgers. No coordinates, keys, URLs or headers.
        var failedRequests: [String: String]?
        var archivedFailedRequests: [String: String]?
    }
    let url: URL
    init(url: URL) { self.url = url }
    private var markerURL: URL { url.appendingPathExtension("initialized") }
    private var markerKey: String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "GPXZBudgetLedger.initialized.\(digest)"
    }
    private func markInitialized() throws {
        // Independent preference survives deletion of the ledger and its sibling marker.
        UserDefaults.standard.set(true, forKey: markerKey)
        guard UserDefaults.standard.synchronize() else { throw TerrainError.ledgerUnavailable }
        do { try Data(markerKey.utf8).write(to: markerURL, options: .atomic) }
        catch { throw TerrainError.ledgerUnavailable }
    }
    private func month(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year!, c.month!)
    }
    private func read(initialize: Bool = true) throws -> Ledger {
        guard FileManager.default.fileExists(atPath: url.path) else {
            guard !UserDefaults.standard.bool(forKey: markerKey),
                  !FileManager.default.fileExists(atPath: markerURL.path) else { throw TerrainError.ledgerUnavailable }
            let ledger = Ledger()
            guard initialize else { return ledger }
            try save(ledger)
            try markInitialized() // First initialization must be durable BEFORE any reservation/send.
            return ledger
        }
        do {
            let ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: url))
            guard ledger.schemaVersion == 1, ledger.months.allSatisfy({ key, value in
                key.count == 7 && key.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil && (0...100).contains(value)
            }), ledger.retryNotBefore?.timeIntervalSince1970.isFinite ?? true,
                  ledger.failedRequests?.allSatisfy({ digest, reason in
                      digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil && reason.count <= 1_000
                  }) ?? true,
                  ledger.archivedFailedRequests?.allSatisfy({ digest, reason in
                      digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil && reason.count <= 1_000
                  }) ?? true else { throw TerrainError.ledgerUnavailable }
            // Bootstrap pre-marker installations only from a validated, existing ledger.
            if initialize { try markInitialized() }
            return ledger
        } catch { throw TerrainError.ledgerUnavailable }
    }
    private func save(_ ledger: Ledger) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger).write(to: url, options: .atomic)
        } catch { throw TerrainError.ledgerUnavailable }
    }
    func quota(now: Date = .now, readOnly: Bool = false) throws -> TerrainQuota {
        let ledger = try read(initialize: !readOnly), m = month(now)
        return TerrainQuota(used: ledger.months[m] ?? 0, month: m)
    }
    func reserve(now: Date = .now) throws {
        var ledger = try read()
        if let date = ledger.retryNotBefore, date > now { throw TerrainError.retryAfter(date) }
        let m = month(now), used = ledger.months[m] ?? 0
        guard used < 100 else { throw TerrainError.exhausted }
        ledger.months[m] = used + 1
        try save(ledger) // Atomic reservation BEFORE dispatch; never refunded on uncertain failure.
    }
    func deferRequests(until date: Date) throws {
        var ledger = try read()
        ledger.retryNotBefore = max(ledger.retryNotBefore ?? date, date)
        try save(ledger)
    }
    func checkFailure(_ fingerprint: String) throws {
        if let reason = try read().failedRequests?[fingerprint] { throw TerrainError.failedRequest(reason) }
    }
    func recordFailure(_ fingerprint: String, reason: String) throws {
        var ledger = try read()
        if ledger.failedRequests == nil { ledger.failedRequests = [:] }
        ledger.failedRequests?[fingerprint] = String(reason.prefix(1_000))
        try save(ledger)
    }
    func clearFailureLocks() throws {
        var ledger = try read()
        // Retain old reasons/digests as history even when explicit consent unlocks retry.
        if let failures = ledger.failedRequests {
            ledger.archivedFailedRequests = (ledger.archivedFailedRequests ?? [:])
                .merging(failures) { _, latest in latest }
        }
        ledger.failedRequests = nil
        // Explicit consent clears ONLY failure locks, never counts, markers or Retry-After.
        try save(ledger)
    }
}

nonisolated struct TerrainFetchResult: Sendable {
    let profile: TerrainProfile?
    let message: String?
    let quota: TerrainQuota?
    let plannedCalls: Int
    var remainingCalls = 0
    var paused = false
}

/// Serial queue spans read/plan/reserve/send/save, including across actor suspension at HTTP.
/// A subsequent overlapping request always replans AFTER its predecessor has persisted.
/// Detached queue jobs deliberately finish saving valid responses even when UI tasks are obsolete.
actor GPXZTerrainRepository {
    static let shared = GPXZTerrainRepository()
    let root: URL
    let client: GPXZElevationClient
    let ledger: GPXZBudgetLedger
    private var tail: Task<Void, Never>?
    private var blockedCourses = Set<String>()
    // Own validated data BEFORE attempting either journal or sidecar writes.
    private var pendingWrites: [String: TerrainCourseCache] = [:]
    private var ledgerBlocked = false

    init(root: URL = CourseDataStore.root, client: GPXZElevationClient? = nil, ledgerURL: URL? = nil) {
        self.root = root
        self.client = client ?? GPXZElevationClient()
        self.ledger = GPXZBudgetLedger(url: ledgerURL ?? root.deletingLastPathComponent()
            .appendingPathComponent("GPXZ", isDirectory: true).appendingPathComponent("monthly-ledger-v1.json"))
    }

    func profile(courseID: String, path: [GeoPoint], straight: Bool,
                 allowPaid: Bool = true,
                 maySend: @escaping @Sendable () -> Bool = { true },
                 dispatch: @escaping @Sendable (@Sendable () -> Void) -> Bool = { start in start(); return true },
                 progress: @escaping @Sendable (TerrainFetchResult) async -> Void = { _ in }) async -> TerrainFetchResult {
        let previous = tail
        let job = Task.detached { [self] in
            await previous?.value
            return await fetch(courseID: courseID, path: path, straight: straight, allowPaid: allowPaid,
                               maySend: maySend, dispatch: dispatch, progress: progress)
        }
        tail = Task.detached { _ = await job.value }
        return await job.value
    }

    /// Serialize consent after already-sent work so its failure cannot race lock clearing.
    func prepareExplicitRetry() async -> String? {
        // Mock retry must not even initialize/read the live ledger or clear its locks.
        guard client.mode == .live else { return nil }
        let previous = tail
        let job = Task.detached { [self] () -> String? in
            await previous?.value
            do { try await ledger.clearFailureLocks(); return nil }
            catch { return TerrainError.ledgerUnavailable.localizedDescription }
        }
        tail = Task.detached { _ = await job.value }
        return await job.value
    }

    private func url(_ courseID: String) -> URL {
        CourseDataStore.directory(courseID: courseID, root: root).appendingPathComponent(
            client.mode == .mock ? "terrain-synthetic-development-v1.json" : "terrain-gpxz-v1.json")
    }
    private func journalURL(_ courseID: String) -> URL { url(courseID).appendingPathExtension("pending") }
    private func flushPending(_ courseID: String) throws {
        do {
            var pending = pendingWrites[courseID]
            if pending == nil, FileManager.default.fileExists(atPath: journalURL(courseID).path) {
                pending = try JSONDecoder().decode(TerrainCourseCache.self, from: Data(contentsOf: journalURL(courseID)))
                try pending?.validate(expectedID: courseID)
                pendingWrites[courseID] = pending
            }
            guard let pending else { return }
            try save(pending)
            if FileManager.default.fileExists(atPath: journalURL(courseID).path) {
                try FileManager.default.removeItem(at: journalURL(courseID))
            }
            pendingWrites.removeValue(forKey: courseID)
            blockedCourses.remove(courseID)
        } catch { blockedCourses.insert(courseID); throw TerrainError.cacheUnavailable }
    }
    private func read(_ courseID: String) throws -> TerrainCourseCache {
        // Storage-only recovery is allowed even while paid acquisition is blocked.
        // Do not spend on another course while received data is stranded in memory.
        for pendingID in Array(pendingWrites.keys).sorted() { try flushPending(pendingID) }
        try flushPending(courseID)
        guard !courseID.isEmpty, !blockedCourses.contains(courseID) else { throw TerrainError.cacheUnavailable }
        let url = url(courseID)
        guard FileManager.default.fileExists(atPath: url.path) else { return TerrainCourseCache(courseID: courseID) }
        do {
            let cache = try JSONDecoder().decode(TerrainCourseCache.self, from: Data(contentsOf: url))
            try cache.validate(expectedID: courseID)
            return cache
        } catch { blockedCourses.insert(courseID); throw TerrainError.cacheUnavailable }
    }
    private func save(_ cache: TerrainCourseCache) throws {
        do {
            let url = url(cache.courseID)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: url, options: .atomic)
        } catch { blockedCourses.insert(cache.courseID); throw TerrainError.cacheUnavailable }
    }
    private func persistReceived(_ cache: TerrainCourseCache) throws {
        pendingWrites[cache.courseID] = cache
        do {
            let journal = journalURL(cache.courseID)
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Full validated snapshot: restart recovery cannot duplicate the appended response.
            try JSONEncoder().encode(cache).write(to: journal, options: .atomic)
            try flushPending(cache.courseID)
        } catch { blockedCourses.insert(cache.courseID); throw TerrainError.cacheUnavailable }
    }

    private func fetch(courseID: String, path: [GeoPoint], straight: Bool, allowPaid: Bool, maySend: @Sendable () -> Bool,
                       dispatch: @Sendable (@Sendable () -> Void) -> Bool,
                       progress: @Sendable (TerrainFetchResult) async -> Void) async -> TerrainFetchResult {
                // Before live cache, failure locks, quota reads/initialization, or any reservation.
                if client.mode == .mock { return await fetchSynthetic(courseID: courseID, path: path, straight: straight, progress: progress) }
                guard !DevelopmentAPIConfiguration.isDemoCourse(courseID),
                            !courseID.hasPrefix(DevelopmentAPIConfiguration.terrainNamespace) else {
                        return TerrainFetchResult(profile: nil,
                                message: "Demo course: live terrain requests are blocked. Select a real course for live testing.", quota: nil, plannedCalls: 0)
                }
        var cache: TerrainCourseCache?
        var plan: TerrainCoveragePlan?
        var planned = 0
        var message: String?
        var paused = false
        do {
            var current = try read(courseID)
            cache = current
            let initial = try TerrainCoveragePlan(path: path, cache: current)
            plan = initial
            if !allowPaid {
                // Opening never builds a remote request, checks credentials/failure locks,
                // initializes the ledger, reserves calls, or schedules paid hole resumption.
                let profile = initial.profile(cache: current, straight: straight)
                let message = initial.uncovered.isEmpty && profile.samples.contains(where: { $0.elevationMeters != nil })
                    ? nil : "Showing saved terrain only. Tap the course map and release a target to load missing shot terrain."
                return TerrainFetchResult(profile: profile, message: message,
                    quota: try? await ledger.quota(readOnly: true), plannedCalls: 0,
                    remainingCalls: initial.uncovered.count)
            }
            planned = initial.uncovered.count
            let before = try? await ledger.quota()
            // Show saved partial coverage and the actual gap count BEFORE any paid dispatch.
            await progress(TerrainFetchResult(profile: initial.profile(cache: current, straight: straight),
                                              message: nil, quota: before, plannedCalls: planned))
            for gap in initial.uncovered {
                guard maySend() else {
                    message = "Showing saved terrain only; some path intervals are unavailable. Commit or refresh explicitly to request uncovered terrain."
                    paused = true
                    break
                }
                guard !ledgerBlocked else { throw TerrainError.ledgerUnavailable }
                let span = TerrainGeometry.slice(initial.path, from: gap.lowerBound, to: gap.upperBound)
                let (request, count) = try client.request(path: span)
                let fingerprint = SHA256.hash(data: request.httpBody ?? Data())
                    .map { String(format: "%02x", $0) }.joined()
                try await ledger.checkFailure(fingerprint) // BEFORE another reservation.
                // Fail closed on storage BEFORE spending, including first-install empty sidecar.
                pendingWrites[courseID] = current
                try flushPending(courseID)
                guard maySend() else { paused = true; break }
                try await ledger.reserve()
                // Superseded while reserving: do not dispatch. Keep the conservative reservation.
                guard maySend() else { paused = true; break }
                do {
                    let record: TerrainResponseRecord
                    do {
                        record = try await client.send(request, path: span, count: count, dispatch: dispatch)
                    } catch {
                        if case TerrainError.requestPaused = error { throw error }
                        // Only client-produced safe errors enter the durable lock. Never URLError URLs.
                        let safe = (error as? TerrainError) ?? TerrainError.transport
                        try await ledger.recordFailure(fingerprint, reason: safe.localizedDescription)
                        throw safe
                    }
                    current.responses.append(record)
                    cache = current
                    // No cancellation check here: a validated superseded response MUST be saved.
                    try persistReceived(current)
                    let partialPlan = try TerrainCoveragePlan(path: initial.path, cache: current)
                    await progress(TerrainFetchResult(profile: partialPlan.profile(cache: current, straight: straight),
                                                      message: nil, quota: try? await ledger.quota(), plannedCalls: planned))
                } catch TerrainError.retryAfter(let date) {
                    try await ledger.deferRequests(until: date)
                    throw TerrainError.retryAfter(date)
                }
            }
            cache = current
            plan = try TerrainCoveragePlan(path: initial.path, cache: current)
            if initial.path.count == 1, current.pointSample(initial.path[0], distance: 0) == nil {
                message = "No saved height at this zero-length path. No height was invented or requested."
            }
        } catch {
            paused = false // Storage/provider/budget failures never become release-triggered retries.
            if case TerrainError.requestPaused = error { paused = true }
            if case TerrainError.ledgerUnavailable = error { ledgerBlocked = true }
            message = error.localizedDescription
            cache = pendingWrites[courseID] ?? cache
            // Preserve successful earlier gaps even if a later request fails or budget runs out.
            if let cache { plan = try? TerrainCoveragePlan(path: path, cache: cache) }
        }
        let quota = try? await ledger.quota(readOnly: !allowPaid)
        if quota == nil && allowPaid { ledgerBlocked = true; paused = false; message = TerrainError.ledgerUnavailable.localizedDescription }
        return TerrainFetchResult(profile: cache.flatMap { c in plan.map { $0.profile(cache: c, straight: straight) } },
                                  message: message, quota: quota, plannedCalls: planned,
                                  remainingCalls: plan?.uncovered.count ?? 0, paused: paused)
    }

    /// Same serialized overlap planner/journal machinery, but a disjoint versioned identity/sidecar.
    /// Cache-only opens may compute synthetic data locally; no paid permit is needed for arithmetic.
    private func fetchSynthetic(courseID: String, path: [GeoPoint], straight: Bool,
                                progress: @Sendable (TerrainFetchResult) async -> Void) async -> TerrainFetchResult {
        let identity = DevelopmentAPIConfiguration.terrainNamespace + courseID
        var cache: TerrainCourseCache?
        do {
            var current = try read(identity)
            cache = current
            let initial = try TerrainCoveragePlan(path: path, cache: current)
            for gap in initial.uncovered {
                let span = TerrainGeometry.slice(initial.path, from: gap.lowerBound, to: gap.upperBound)
                let (request, count) = try client.request(path: span)
                let record = try await client.send(request, path: span, count: count)
                current.responses.append(record)
                try current.validate(expectedID: identity)
                cache = current
                try persistReceived(current)
            }
            if initial.path.count == 1, let point = initial.path.first {
                // Coincident paths are local arithmetic, never a fabricated live provider response.
                let source = TerrainProvenance(dataSource: DevelopmentAPIConfiguration.syntheticSource,
                    resolutionMeters: 1, captureDateMin: nil, captureDateMax: nil, datasetVersion: "synthetic-development-v1",
                    fetchedAt: .now, interpolation: "analytical synthetic surface", verticalDatum: "Synthetic (not surveyed)",
                    providerSampleIntervalMeters: 1)
                return TerrainFetchResult(profile: TerrainProfile(samples: [TerrainSample(distanceMeters: 0, point: point,
                    elevationMeters: GPXZElevationClient.syntheticElevation(at: point), provenance: [source])], isStraightLine: straight),
                    message: nil, quota: nil, plannedCalls: 0)
            }
            let profile = try TerrainCoveragePlan(path: path, cache: current).profile(cache: current, straight: straight)
            let result = TerrainFetchResult(profile: profile, message: nil, quota: nil, plannedCalls: 0)
            await progress(result)
            return result
        } catch {
            let profile = cache.flatMap { cache in (try? TerrainCoveragePlan(path: path, cache: cache))?.profile(cache: cache, straight: straight) }
            return TerrainFetchResult(profile: profile, message: "Demo terrain storage: \(error.localizedDescription)", quota: nil, plannedCalls: 0)
        }
    }
}