import Foundation

/// Captured local inputs, not live bindings. Endpoint provenance is kept with the result.
struct CourseShotRecommendationInput: Equatable {
    let request: TerrainRequest
    let weather: CourseWeather
    let weatherLocation: GeoPoint
    let originSample: TerrainSample
    let targetSample: TerrainSample
    let profile: TrajectoryPlayerProfile
    let wedges: [Wedge]
    let distanceM: Double
    let bearingDeg: Double
    let scoringPlan: ScoringShotPlan
    let usesWind: Bool
    let usesElevation: Bool

    var isScoring: Bool { scoringPlan.isScoring(distanceM: distanceM) }

    var conditions: ClubRecommendationConditions {
        let wind = Self.wind(speedMps: weather.windSpeedMps!, fromDeg: weather.windDirectionDegrees!, bearingDeg: bearingDeg)
        return ClubRecommendationConditions(
            temperatureC: weather.temperatureC!, pressureInputMode: .pressure,
            pressureHpa: weather.surfacePressureHpa!, siteElevationM: originSample.elevationMeters!,
            humidityPct: weather.relativeHumidityPercent!,
            tailwindMps: usesWind ? wind.tail : 0,
            crosswindMps: usesWind ? wind.right : 0,
            elevationDeltaM: usesElevation ? targetSample.elevationMeters! - originSample.elevationMeters! : 0)
    }

    /// Meteorological FROM, clockwise from true north. Physics x is toward the
    /// target and y is right. Keep m/s (weather card's km/h is display-only).
    static func wind(speedMps: Double, fromDeg: Double, bearingDeg: Double) -> (tail: Double, right: Double) {
        let angle = (fromDeg - bearingDeg) * .pi / 180
        return (-speedMps * cos(angle), -speedMps * sin(angle))
    }

    // Legacy live-origin arguments remain source-compatible but cannot invalidate
    // a committed shot. Only the request's captured origin/source defines advice.
    static func capture(request: TerrainRequest?, selectedTarget: GeoPoint?, liveOrigin _: GeoPoint? = nil,
                        usesGPS _: Bool = false, weather: CourseWeather?, weatherLocation: GeoPoint?,
                        shotProfile: TerrainProfile?, profile: TrajectoryPlayerProfile, wedges: [Wedge] = [],
                        usesWind: Bool = true, usesElevation: Bool = true) -> Self? {
        let adviceProfile = profileForCourseAdvice(profile)
        let scoringPlan = ScoringShotPlan.make(profile: adviceProfile, wedges: wedges)
        guard let request, let selectedTarget, let origin = request.origin,
              request.target == selectedTarget,
              let weatherLocation, let weather, valid(weather),
              let first = shotProfile?.samples.first, let last = shotProfile?.samples.last,
              TerrainGeometry.length(first.point, origin) <= TerrainGeometry.tolerance,
              TerrainGeometry.length(last.point, selectedTarget) <= TerrainGeometry.tolerance,
              let originHeight = first.elevationMeters, originHeight.isFinite,
              let targetHeight = last.elevationMeters, targetHeight.isFinite,
              adviceProfile.isSetupComplete else { return nil }
        let distance = GolfGeometry.distance(origin, selectedTarget)
        guard distance.isFinite, distance > 0.1 else { return nil }
        guard profileIssue(adviceProfile) == nil || scoringPlan.isScoring(distanceM: distance) else { return nil }
        return Self(request: request, weather: weather, weatherLocation: weatherLocation,
                    originSample: first, targetSample: last, profile: adviceProfile, wedges: wedges, distanceM: distance,
                                        bearingDeg: GolfGeometry.bearing(from: origin, to: selectedTarget), scoringPlan: scoringPlan,
                                        usesWind: usesWind, usesElevation: usesElevation)
    }

    /// Course advice remains available before the golfer has configured a profile.
    /// Incomplete/empty profiles use the same explicit simple defaults as Practice,
    /// without writing setup state back to the user's saved profile.
    private static func profileForCourseAdvice(_ profile: TrajectoryPlayerProfile) -> TrajectoryPlayerProfile {
        guard profileIssue(profile) != nil else { return profile }
        var defaults = profile
        defaults.isSetupComplete = true
        defaults.detailLevel = .easy
        defaults.availableClubs = TrajectoryGolfClub.standardBag
        return defaults
    }

    static func valid(_ weather: CourseWeather) -> Bool {
        guard let temperature = weather.temperatureC, temperature.isFinite, temperature > -100, temperature < 100,
              let pressure = weather.surfacePressureHpa, pressure.isFinite, pressure > 0,
              let humidity = weather.relativeHumidityPercent, humidity.isFinite, (0...100).contains(humidity),
              let speed = weather.windSpeedMps, speed.isFinite, speed >= 0,
              let direction = weather.windDirectionDegrees, direction.isFinite, (0...360).contains(direction) else { return false }
        return true
    }

    static func profileIssue(_ profile: TrajectoryPlayerProfile) -> String? {
        guard profile.isSetupComplete else { return "Set up your Practice golfer profile first; no generic prediction is shown." }
        guard !profile.availableClubs.isEmpty else { return "No clubs in your Practice bag. Configure your profile first." }
        // Simple is an explicitly chosen handicap-default mode. The other levels
        // must have an anchor consumed by Practice's actual effective-profile logic.
        let hasCarry = profile.clubOverrides.values.contains {
            ($0.carryDistanceM.map { $0.isFinite && $0 > 0 }) == true
        }
        if profile.detailLevel == .medium, !hasCarry {
            return "Enter a club carry calibration in Practice / Profile before using your Medium profile."
        }
        let hasLaunch = profile.clubOverrides.values.contains {
            [$0.ballSpeedMps, $0.launchAngleDeg, $0.spinRateRpm, $0.spinAxisDeg].contains { $0?.isFinite == true }
        }
        if profile.detailLevel == .expert, !hasCarry, !hasLaunch {
            return "Enter club launch data or carry calibration in Practice / Profile before using your Advanced profile."
        }
        return nil
    }
}

struct CourseShotRecommendationResult {
    let input: CourseShotRecommendationInput
    let recommendations: [CourseClubRecommendation]
    var unavailableScoringShots: [UnavailableScoringShot] = []
}