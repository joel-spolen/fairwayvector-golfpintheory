import Foundation
import Observation

enum TerrainProfileMode: String, CaseIterable, Identifiable {
    case hole = "Hole", shot = "Current shot"
    var id: Self { self }
}

/// Profiles are sampled locally from the course elevation downloaded with the course.
/// GPS/draft movement never changes a committed shot; only a released target does.
@MainActor @Observable
final class TerrainElevationStore {
    private(set) var snapshot = TerrainSnapshot()
    private(set) var isHoleLoading = false
    private(set) var isShotLoading = false
    private(set) var shotPending = false
    private(set) var holeMessage: String?
    private(set) var shotMessage: String?
    private(set) var committedRequest: TerrainRequest?
    var mode: TerrainProfileMode = .hole
    var isLoading: Bool { mode == .hole ? isHoleLoading : isShotLoading }
    var statusMessage: String? { mode == .hole ? holeMessage : shotMessage }
    var usesGPS: Bool { committedRequest?.usesGPS == true }

    @ObservationIgnored private var terrain: CourseTerrain?
    @ObservationIgnored private var unavailableMessage: String?
    @ObservationIgnored private var targetInteractionActive = false

    /// `loading` keeps profiles pending while the course elevation is still downloading.
    func setTerrain(_ terrain: CourseTerrain?, unavailableMessage: String?, loading: Bool = false) {
        self.terrain = terrain
        self.unavailableMessage = unavailableMessage
        isHoleLoading = loading
        isShotLoading = loading
    }

    func open(_ request: TerrainRequest, resetHole: Bool = true) {
        invalidateShot(showHole: resetHole)
        shotPending = false
        shotMessage = nil
        if resetHole { snapshot = TerrainSnapshot(); mode = .hole }
        snapshot.holeProfile = profile(request.path, straight: request.usesPointOnlyGeometry)
        holeMessage = message(for: snapshot.holeProfile)
        commitShot(request, selectShot: false)
    }

    func deactivate() {
        targetInteractionActive = false
        invalidateShot()
    }

    func beginTargetInteraction() {
        targetInteractionActive = true
        invalidateShot()
    }

    /// A cancelled recognizer is not a release commit.
    func cancelTargetInteraction() {
        guard targetInteractionActive else { return }
        targetInteractionActive = false
        shotPending = false
        shotMessage = L("Tap the map to choose a target.")
    }

    func invalidateShot(showHole: Bool = true) {
        if showHole { mode = .hole }
        snapshot.shotProfile = nil
        snapshot.targetToFlagProfile = nil
        committedRequest = nil
        // Invalidating cached advice (hole change/deactivation) is not a held gesture.
        shotPending = targetInteractionActive
        shotMessage = targetInteractionActive ? L("Release to see the elevation.") : nil
    }

    func commitShot(_ request: TerrainRequest, selectShot: Bool = true) {
        targetInteractionActive = false
        invalidateShot(showHole: false)
        committedRequest = request // labels use this immutable origin, NOT a newer live GPS fix
        if selectShot { mode = .shot }
        guard let origin = request.origin, let target = request.target else {
            shotMessage = L("Tap the map to choose a target.")
            return
        }
        snapshot.shotProfile = profile([origin, target], straight: true)
        if let flag = request.flag, target != flag {
            snapshot.targetToFlagProfile = profile([target, flag], straight: true)
        }
        shotMessage = message(for: snapshot.shotProfile)
    }

    private func profile(_ path: [GeoPoint], straight: Bool) -> TerrainProfile? {
        terrain?.profile(path: path, straight: straight)
    }

    private func message(for profile: TerrainProfile?) -> String? {
        guard terrain != nil else { return isHoleLoading ? nil : unavailableMessage ?? L("Terrain unavailable") }
        guard let profile, profile.samples.first?.elevationMeters != nil,
              profile.samples.last?.elevationMeters != nil else {
            return L("No elevation data for this spot.")
        }
        return nil
    }
}
