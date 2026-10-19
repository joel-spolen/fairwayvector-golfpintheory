import Combine
import Foundation
import SwiftUI

/// How the effective station pressure is determined: typed directly, or derived
/// from a site elevation via the standard atmosphere formula.
enum PressureInputMode: String, CaseIterable, Identifiable {
    case pressure
    case elevation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pressure: return "Pressure"
        case .elevation: return "Site Elevation"
        }
    }
}

private struct CalculationInputSnapshot {
    let ballSpeedMps: Double
    let launchAngleDeg: Double
    let launchDirectionDeg: Double
    let spinRateRpm: Double
    let spinAxisDeg: Double
    let temperatureC: Double
    let pressureInputMode: PressureInputMode
    let pressureHpa: Double
    let siteElevationM: Double
    let humidityPct: Double
    let tailwindMps: Double
    let crosswindMps: Double
    let elevationDeltaM: Double
}

private struct PersistedTrajectoryConditions: Codable {
    let temperatureC: Double
    let pressureInputModeRawValue: String
    let pressureHpa: Double
    let siteElevationM: Double
    let humidityPct: Double
    let tailwindMps: Double
    let crosswindMps: Double
    let elevationDeltaM: Double
}

nonisolated struct ClubRecommendation: Identifiable, Sendable {
    let club: TrajectoryGolfClub
    let estimatedCarryM: Double
    let differenceM: Double
    let trajectory: GolfTrajectory
    let targetElevationM: Double
    let heightAtTargetDistanceM: Double?
    let lateralAtTargetDistanceM: Double?
    let prediction: HybridPrediction

    var id: TrajectoryGolfClub { club }
}

struct ClubRecommendationConditions: Equatable {
    var temperatureC: Double = 20.0
    var pressureInputMode: PressureInputMode = .elevation
    var pressureHpa: Double = 1013.25
    var siteElevationM: Double = 0.0
    var humidityPct: Double = 50.0
    var tailwindMps: Double = 0.0
    var crosswindMps: Double = 0.0
    var elevationDeltaM: Double = 0.0

    func effectivePressureHpa() throws -> Double {
        switch pressureInputMode {
        case .pressure:
            return pressureHpa
        case .elevation:
            return try Atmosphere.standardPressureHpa(fromAltitudeM: siteElevationM)
        }
    }
}

/// Owns shot input state in canonical metric units (matching `ShotInputs`) and
/// drives a single `HybridPredictor` calculation. Views convert to/from the
/// active `UnitPreferences` for display only.
@MainActor
final class TrajectoryCalculatorViewModel: ObservableObject {
    @Published var ballSpeedMps: Double = Units.mpsFromMph(150.0)
    @Published var launchAngleDeg: Double = 12.0
    @Published var launchDirectionDeg: Double = 0.0
    @Published var spinRateRpm: Double = 2700.0
    @Published var spinAxisDeg: Double = 0.0
    @Published var activeClub: TrajectoryGolfClub = .driver {
        didSet { applyActiveClubProfile(clearPrediction: false) }
    }

    // Environment & wind, defaulted to the TrackMan reference conditions used
    // during model development.
    @Published var pressureInputMode: PressureInputMode = .elevation {
        didSet {
            if pressureInputMode == .elevation {
                syncPressureFromElevation()
            }
            savePersistedConditions()
        }
    }
    @Published var pressureHpa: Double = 1013.25 {
        didSet {
            syncElevationFromPressure()
            savePersistedConditions()
        }
    }
    @Published var siteElevationM: Double = 0.0 {
        didSet {
            syncPressureFromElevation()
            savePersistedConditions()
        }
    }
    @Published var temperatureC: Double = 20.0 { didSet { savePersistedConditions() } }
    @Published var humidityPct: Double = 50.0 { didSet { savePersistedConditions() } }
    @Published var tailwindMps: Double = 0.0 { didSet { savePersistedConditions() } }
    @Published var crosswindMps: Double = 0.0 { didSet { savePersistedConditions() } }
    @Published var elevationDeltaM: Double = 0.0 { didSet { savePersistedConditions() } }

    let unitPreferences = UnitPreferences()
    let playerProfileStore: PlayerProfileStore

    @Published private(set) var prediction: HybridPrediction?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCalculating = false
    private(set) var lastCalculationBallSpeedMps: Double?

    private var predictor: HybridPredictor?
    private let recommendationEngine = ClubRecommendationEngine()
    private var loadError: Error?
    private var cancellables = Set<AnyCancellable>()
    private var isSyncingAtmosphere = false
    private var isRestoringPersistedConditions = false
    private var lastCalculationInputs: CalculationInputSnapshot?
    private let userDefaults: UserDefaults

    init(playerProfileStore: PlayerProfileStore? = nil, userDefaults: UserDefaults = .standard) {
        self.playerProfileStore = playerProfileStore ?? PlayerProfileStore()
        self.userDefaults = userDefaults
        do {
            predictor = try HybridPredictor()
        } catch {
            loadError = error
        }
        // Forward nested UnitPreferences changes so views observing this view model re-render.
        unitPreferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        self.playerProfileStore.$profile
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyActiveClubProfile(clearPrediction: false)
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        if self.playerProfileStore.profile.isSetupComplete {
            applyActiveClubProfile(clearPrediction: false)
        }
        restorePersistedConditions()
    }

    func applyActiveClubProfile(clearPrediction: Bool = true) {
        guard playerProfileStore.profile.isSetupComplete else { return }
        let profile = playerProfileStore.effectiveProfile(for: activeClub)
        ballSpeedMps = profile.ballSpeedMps.value
        launchAngleDeg = profile.launchAngleDeg.value
        spinRateRpm = profile.spinRateRpm.value
        spinAxisDeg = profile.spinAxisDeg.value
        if clearPrediction {
            prediction = nil
        }
        errorMessage = nil
    }

    /// The station pressure actually used by the simulator: either typed directly,
    /// or derived from `siteElevationM` via the standard atmosphere formula.
    func effectivePressureHpa() throws -> Double {
        switch pressureInputMode {
        case .pressure:
            return pressureHpa
        case .elevation:
            return try Atmosphere.standardPressureHpa(fromAltitudeM: siteElevationM)
        }
    }

    /// Keeps the Pressure field showing the standard-atmosphere value implied by the
    /// current elevation, so switching input modes doesn't show a stale pressure.
    /// Once a user types a pressure directly, the two are free to diverge again.
    private func syncPressureFromElevation() {
        guard !isSyncingAtmosphere else { return }
        if let derived = try? Atmosphere.standardPressureHpa(fromAltitudeM: siteElevationM) {
            isSyncingAtmosphere = true
            pressureHpa = derived
            isSyncingAtmosphere = false
        }
    }

    private func syncElevationFromPressure() {
        guard !isSyncingAtmosphere else { return }
        if let derived = try? Atmosphere.altitudeM(fromStandardPressureHpa: pressureHpa) {
            isSyncingAtmosphere = true
            siteElevationM = derived
            isSyncingAtmosphere = false
        }
    }

    private func savePersistedConditions() {
        guard !isRestoringPersistedConditions else { return }
        let conditions = PersistedTrajectoryConditions(
            temperatureC: temperatureC,
            pressureInputModeRawValue: pressureInputMode.rawValue,
            pressureHpa: pressureHpa,
            siteElevationM: siteElevationM,
            humidityPct: humidityPct,
            tailwindMps: tailwindMps,
            crosswindMps: crosswindMps,
            elevationDeltaM: elevationDeltaM
        )
        guard let data = try? JSONEncoder().encode(conditions) else { return }
        userDefaults.set(data, forKey: "trajectory.lastConditions")
    }

    private func restorePersistedConditions() {
        guard let data = userDefaults.data(forKey: "trajectory.lastConditions"),
              let conditions = try? JSONDecoder().decode(PersistedTrajectoryConditions.self, from: data) else {
            return
        }

        isRestoringPersistedConditions = true
        temperatureC = conditions.temperatureC
        pressureInputMode = PressureInputMode(rawValue: conditions.pressureInputModeRawValue) ?? .elevation
        pressureHpa = conditions.pressureHpa
        siteElevationM = conditions.siteElevationM
        humidityPct = conditions.humidityPct
        tailwindMps = conditions.tailwindMps
        crosswindMps = conditions.crosswindMps
        elevationDeltaM = conditions.elevationDeltaM
        isRestoringPersistedConditions = false
    }

    func currentShotInputs(includeAdvancedConditions: Bool = true) throws -> ShotInputs {
        let effectiveTemperatureC = includeAdvancedConditions ? temperatureC : 20.0
        let effectivePressureHpa = includeAdvancedConditions ? try effectivePressureHpa() : 1013.25
        let effectiveHumidityPct = includeAdvancedConditions ? humidityPct : 50.0
        let effectiveCrosswindMps = includeAdvancedConditions ? crosswindMps : 0.0
        return ShotInputs(
            ballSpeedMps: ballSpeedMps,
            launchAngleDeg: launchAngleDeg,
            launchDirectionDeg: launchDirectionDeg,
            spinRateRpm: spinRateRpm,
            spinAxisDeg: spinAxisDeg,
            temperatureC: effectiveTemperatureC,
            pressureHpa: effectivePressureHpa,
            relativeHumidityPct: effectiveHumidityPct,
            windXMps: tailwindMps,
            windYMps: effectiveCrosswindMps,
            windZMps: 0.0,
            targetElevationDeltaM: elevationDeltaM
        )
    }

    func recommendClub(for targetCarryM: Double, conditions: ClubRecommendationConditions,
                       profile: TrajectoryPlayerProfile? = nil) async throws -> [ClubRecommendation] {
        let launches = try ClubRecommendationEngine.launches(profile: profile ?? playerProfileStore.profile, conditions: conditions)
        return try await recommendationEngine.recommend(for: targetCarryM, launches: launches)
    }

    func prepareTrajectory(for club: TrajectoryGolfClub, conditions: ClubRecommendationConditions) {
        activeClub = club
        applyActiveClubProfile(clearPrediction: true)

        temperatureC = conditions.temperatureC
        pressureInputMode = conditions.pressureInputMode
        siteElevationM = conditions.siteElevationM
        pressureHpa = conditions.pressureHpa
        humidityPct = conditions.humidityPct
        tailwindMps = conditions.tailwindMps
        crosswindMps = conditions.crosswindMps
        elevationDeltaM = conditions.elevationDeltaM
        errorMessage = nil
    }

    func calculate(includeAdvancedConditions: Bool = true) {
        guard !isCalculating else { return }
        errorMessage = nil
        guard let predictor else {
            errorMessage = loadError?.localizedDescription ?? "Prediction models failed to load."
            return
        }
        guard ballSpeedMps > 0 else {
            errorMessage = "Ball speed must be greater than zero."
            return
        }
        guard spinRateRpm >= 0 else {
            errorMessage = "Spin rate cannot be negative."
            return
        }

        isCalculating = true
        let inputSnapshot = CalculationInputSnapshot(
            ballSpeedMps: ballSpeedMps,
            launchAngleDeg: launchAngleDeg,
            launchDirectionDeg: launchDirectionDeg,
            spinRateRpm: spinRateRpm,
            spinAxisDeg: spinAxisDeg,
            temperatureC: temperatureC,
            pressureInputMode: pressureInputMode,
            pressureHpa: pressureHpa,
            siteElevationM: siteElevationM,
            humidityPct: humidityPct,
            tailwindMps: tailwindMps,
            crosswindMps: crosswindMps,
            elevationDeltaM: elevationDeltaM
        )
        Task { @MainActor in
            await Task.yield()
            do {
                prediction = try predictor.predict(try currentShotInputs(includeAdvancedConditions: includeAdvancedConditions))
                lastCalculationInputs = inputSnapshot
                lastCalculationBallSpeedMps = inputSnapshot.ballSpeedMps
            } catch {
                errorMessage = error.localizedDescription
                prediction = nil
            }
            isCalculating = false
        }
    }

    func randomizeExampleShot() {
        ballSpeedMps = Double.random(in: Units.mpsFromMph(100)...Units.mpsFromMph(175))
        launchAngleDeg = Double.random(in: 8...18)
        launchDirectionDeg = Double.random(in: -8...8)
        spinRateRpm = Double.random(in: 1800...4200)
        spinAxisDeg = Double.random(in: -12...12)
        temperatureC = Double.random(in: 10...30)
        pressureInputMode = .elevation
        siteElevationM = Double.random(in: -100...3000)
        humidityPct = Double.random(in: 30...80)
        tailwindMps = Double.random(in: Units.mpsFromMph(-10)...Units.mpsFromMph(15))
        crosswindMps = Double.random(in: Units.mpsFromMph(-10)...Units.mpsFromMph(10))
        elevationDeltaM = Double.random(in: Units.metersFromFeet(-30)...Units.metersFromFeet(30))
        calculate()
    }

    func resetInputs(clearPrediction: Bool = true) {
        if playerProfileStore.profile.isSetupComplete {
            applyActiveClubProfile(clearPrediction: clearPrediction)
        } else {
            ballSpeedMps = Units.mpsFromMph(150.0)
            launchAngleDeg = 12.0
            spinRateRpm = 2700.0
            spinAxisDeg = 0.0
        }
        launchDirectionDeg = 0.0
        temperatureC = 20.0
        pressureInputMode = .elevation
        siteElevationM = 0.0
        humidityPct = 50.0
        tailwindMps = 0.0
        crosswindMps = 0.0
        elevationDeltaM = 0.0
        if clearPrediction {
            prediction = nil
        }
        errorMessage = nil
    }

    func restoreLastCalculationInputs() {
        guard let snapshot = lastCalculationInputs else { return }

        isSyncingAtmosphere = true
        ballSpeedMps = snapshot.ballSpeedMps
        launchAngleDeg = snapshot.launchAngleDeg
        launchDirectionDeg = snapshot.launchDirectionDeg
        spinRateRpm = snapshot.spinRateRpm
        spinAxisDeg = snapshot.spinAxisDeg
        temperatureC = snapshot.temperatureC
        pressureInputMode = snapshot.pressureInputMode
        pressureHpa = snapshot.pressureHpa
        siteElevationM = snapshot.siteElevationM
        humidityPct = snapshot.humidityPct
        tailwindMps = snapshot.tailwindMps
        crosswindMps = snapshot.crosswindMps
        elevationDeltaM = snapshot.elevationDeltaM
        isSyncingAtmosphere = false
        errorMessage = nil
    }
}
