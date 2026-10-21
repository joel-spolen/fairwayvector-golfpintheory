import Foundation
import Observation

nonisolated final class TerrainRequestPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    let allowPaid: Bool
    init(allowPaid: Bool = true) { self.allowPaid = allowPaid }
    func invalidate() { lock.lock(); active = false; lock.unlock() }
    func setActive(_ value: Bool) { lock.lock(); active = value; lock.unlock() }
    func maySend() -> Bool { lock.lock(); defer { lock.unlock() }; return active && allowPaid }
    func performIfActive(_ start: @Sendable () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard active && allowPaid else { return false }
        start()
        return true
    }
    func dispatch(if permit: TerrainRequestPermit, _ start: @Sendable () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard active && allowPaid else { return false }
        return permit.performIfActive(start)
    }
}

enum TerrainProfileMode: String, CaseIterable, Identifiable {
    case hole = "Hole", shot = "Current shot"
    var id: Self { self }
}

/// Hole and committed-shot state have independent generations. GPS/draft movement is NOT a request.
@MainActor @Observable
final class TerrainElevationStore {
    private(set) var snapshot = TerrainSnapshot()
    private(set) var isHoleLoading = false
    private(set) var isShotLoading = false
    private(set) var shotPending = false
    private(set) var holeMessage: String?
    private(set) var shotMessage: String?
    private(set) var committedRequest: TerrainRequest?
    private(set) var quota: TerrainQuota?
    private(set) var plannedCalls = 0
    var mode: TerrainProfileMode = .hole
    var isLoading: Bool { mode == .hole ? isHoleLoading : isShotLoading }
    var statusMessage: String? { mode == .hole ? holeMessage : shotMessage }
    var metadata: [TerrainProvenance] { selectedProfile?.metadata ?? [] }
    var selectedProfile: TerrainProfile? { mode == .hole ? snapshot.holeProfile : snapshot.shotProfile }
    var usesGPS: Bool { committedRequest?.usesGPS == true }

    @ObservationIgnored private let repository: GPXZTerrainRepository
    @ObservationIgnored private var holeGeneration = 0
    @ObservationIgnored private var shotGeneration = 0
    @ObservationIgnored private var holePermit = TerrainRequestPermit()
    @ObservationIgnored private var shotPermit = TerrainRequestPermit()
    @ObservationIgnored private let interactionGate = TerrainRequestPermit()
    @ObservationIgnored private var targetInteractionActive = false
    @ObservationIgnored private var lastHoleRequest: TerrainRequest?

    init(repository: GPXZTerrainRepository = .shared) { self.repository = repository }

    func open(_ request: TerrainRequest, resetHole: Bool = true) {
        // A concurrent refresh/geometry update must not reopen dispatch mid-drag.
        interactionGate.setActive(!targetInteractionActive)
        lastHoleRequest = request
        invalidateShot(showHole: resetHole)
        shotPending = false
        shotMessage = nil // Old HTTP status is UI state, not deletion of failure history.
        plannedCalls = 0
        if resetHole { snapshot = TerrainSnapshot(); mode = .hole }
        committedRequest = nil
        loadHole(request, initializeShot: true)
    }

    private func loadHole(_ request: TerrainRequest, initializeShot: Bool) {
        holeGeneration += 1
        let generation = holeGeneration
        holePermit.invalidate()
        holePermit = TerrainRequestPermit(allowPaid: false)
        let initialShotGeneration = shotGeneration
        holeMessage = nil
        isHoleLoading = true
        let permit = holePermit
        let gate = interactionGate
        Task {
            let result = await repository.profile(courseID: request.courseID, path: request.path,
                straight: request.usesPointOnlyGeometry, allowPaid: permit.allowPaid,
                maySend: { permit.maySend() && gate.maySend() },
                dispatch: { start in gate.dispatch(if: permit, start) }, progress: { [weak self] partial in
                    await self?.publishHole(partial, generation: generation)
                })
            guard holeGeneration == generation else { return }
            if let profile = result.profile { snapshot.holeProfile = profile }
            holeMessage = result.message
            quota = result.quota
            if mode == .hole { plannedCalls = result.plannedCalls }
            isHoleLoading = false
            if initializeShot && shotGeneration == initialShotGeneration && gate.maySend() {
                commitShot(request, selectShot: false, allowPaid: false)
            }
        }
    }

    /// Called ONLY from the confirmed retry UI; preserves the existing budget and backoff.
    func retryFailedRequests(_ request: TerrainRequest) {
        let generation = holeGeneration
        let shot = shotGeneration
        Task {
            let message = await repository.prepareExplicitRetry()
            guard holeGeneration == generation, shotGeneration == shot, !targetInteractionActive else { return }
            if let message { holeMessage = message; shotMessage = message }
            else { commitShot(request, allowPaid: true) }
        }
    }

    func deactivate() {
        holeGeneration += 1
        holePermit.invalidate()
        interactionGate.setActive(false)
        targetInteractionActive = false
        lastHoleRequest = nil
        invalidateShot()
        isHoleLoading = false
    }

    private func publishHole(_ result: TerrainFetchResult, generation: Int) {
        guard holeGeneration == generation else { return }
        snapshot.holeProfile = result.profile
        quota = result.quota
        if mode == .hole { plannedCalls = result.plannedCalls }
    }

    private func publishShot(_ result: TerrainFetchResult, generation: Int) {
        guard shotGeneration == generation else { return }
        snapshot.shotProfile = result.profile
        quota = result.quota
        plannedCalls = result.plannedCalls
    }

    private func publishNext(_ result: TerrainFetchResult, generation: Int, precedingCalls: Int) {
        guard shotGeneration == generation else { return }
        snapshot.targetToFlagProfile = result.profile
        quota = result.quota
        plannedCalls = precedingCalls + result.plannedCalls
    }

    /// Stop BOTH dispatch pipelines, preserving the displayed hole and its pending load.
    func beginTargetInteraction() {
        targetInteractionActive = true
        interactionGate.setActive(false)
        holePermit.invalidate()
        invalidateShot()
    }

    /// A cancelled recognizer is not a release commit and must not acquire data.
    func cancelTargetInteraction() {
        guard targetInteractionActive else { return }
        targetInteractionActive = false
        interactionGate.setActive(true)
        shotPending = false
        shotMessage = "Target movement cancelled. Tap the map and release a target to commit its terrain."
    }

    /// Invalidate obsolete shot state without changing the hole pipeline or interaction gate.
    func invalidateShot(showHole: Bool = true) {
        shotGeneration += 1
        shotPermit.invalidate()
        if showHole { mode = .hole }
        snapshot.shotProfile = nil
        snapshot.targetToFlagProfile = nil
        committedRequest = nil
        isShotLoading = false
        // Invalidating cached advice (hole change/deactivation) is not a held gesture.
        shotPending = targetInteractionActive
        shotMessage = targetInteractionActive ? "Target is being moved. Release to load its terrain." : nil
    }

    func commitShot(_ request: TerrainRequest, selectShot: Bool = true, allowPaid: Bool = true) {
        targetInteractionActive = false
        interactionGate.setActive(true)
        invalidateShot(showHole: false)
        let generation = shotGeneration
        shotPermit = TerrainRequestPermit(allowPaid: allowPaid)
        let permit = shotPermit
        let gate = interactionGate
        committedRequest = request // labels use this immutable origin, NOT a newer live GPS fix
        if selectShot { mode = .shot }
        shotPending = false
        shotMessage = nil
        plannedCalls = 0
        guard let origin = request.origin, let target = request.target else {
            shotMessage = allowPaid ? "No committed shot origin or target is available."
                : "Showing saved terrain only. Tap the course map and release a target to load missing shot terrain."
            return
        }
        isShotLoading = true
        Task {
            let shot = await repository.profile(courseID: request.courseID, path: [origin, target], straight: true,
                allowPaid: permit.allowPaid,
                maySend: { allowPaid && permit.maySend() && gate.maySend() },
                dispatch: { start in allowPaid && gate.dispatch(if: permit, start) }, progress: { [weak self] partial in
                    await self?.publishShot(partial, generation: generation)
                })
            guard shotGeneration == generation else { return }
            snapshot.shotProfile = shot.profile
            shotMessage = shot.message
            quota = shot.quota
            plannedCalls = shot.plannedCalls
            if (!allowPaid || shot.message == nil), let flag = request.flag, target != flag,
               gate.maySend() {
                let next = await repository.profile(courseID: request.courseID, path: [target, flag], straight: true,
                    allowPaid: permit.allowPaid,
                    maySend: { allowPaid && shot.message == nil && permit.maySend() && gate.maySend() },
                    dispatch: { start in allowPaid && shot.message == nil && gate.dispatch(if: permit, start) }, progress: { [weak self] partial in
                        await self?.publishNext(partial, generation: generation, precedingCalls: shot.plannedCalls)
                    })
                guard shotGeneration == generation else { return }
                snapshot.targetToFlagProfile = next.profile
                shotMessage = shot.message ?? next.message
                quota = next.quota
                plannedCalls = shot.plannedCalls + next.plannedCalls
            }
            isShotLoading = false
            // Newly saved shot coverage may contribute to the hole chart, but never
            // acquire unrelated hole gaps, including on the very first map tap.
            if allowPaid, let hole = lastHoleRequest { loadHole(hole, initializeShot: false) }
        }
    }
}