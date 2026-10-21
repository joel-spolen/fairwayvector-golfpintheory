import XCTest
@testable import fairwayvector_golfpintheory

/// Offline source only. No provider clients, live caches or real user defaults.
@MainActor
final class CourseShotRecommendationTests: XCTestCase {
    private let origin = GeoPoint(lat: 57.62, lon: 12.0)
    private let target = GeoPoint(lat: 57.6215, lon: 12.0)

    private func weather(pressure: Double? = 900, direction: Double? = 0) -> CourseWeather {
        CourseWeather(elevationMeters: 1234, timezone: "UTC", observedAt: "2026-10-05T10:00",
                      temperatureC: 15, relativeHumidityPercent: 60, surfacePressureHpa: pressure,
                      seaLevelPressureHpa: 1015, windSpeedMps: 5, windDirectionDegrees: direction,
                      windGustsMps: 12)
    }

    private func request() -> TerrainRequest {
        TerrainRequest(courseID: "offline-fixture", holeNumber: 1, path: [origin, target], flag: target,
                       origin: origin, target: target, usesPointOnlyGeometry: true, usesGPS: true)
    }

    private func terrain(originHeight: Double = 400, targetHeight: Double = 410) -> TerrainProfile {
        TerrainProfile(samples: [TerrainSample(distanceMeters: 0, point: origin, elevationMeters: originHeight),
            TerrainSample(distanceMeters: TerrainGeometry.length(origin, target), point: target, elevationMeters: targetHeight)],
                       isStraightLine: true)
    }

    private func capture(weather: CourseWeather? = nil, terrain: TerrainProfile? = nil,
                         selected: GeoPoint? = nil, liveOrigin: GeoPoint? = nil,
                         profile: TrajectoryPlayerProfile? = nil) -> CourseShotRecommendationInput? {
        CourseShotRecommendationInput.capture(request: request(), selectedTarget: selected ?? target,
            liveOrigin: liveOrigin ?? origin, usesGPS: true, weather: weather ?? self.weather(),
            weatherLocation: origin, shotProfile: terrain ?? self.terrain(),
            profile: profile ?? TrajectoryPlayerProfile(isSetupComplete: true, availableClubs: [.sevenIron, .eightIron, .nineIron]))
    }

    func testMeteorologicalWindRotation() {
        let cases: [(Double, Double, Double, Double)] = [
            (0, 0, -5, 0), (180, 0, 5, 0), (90, 0, 0, -5), (270, 0, 0, 5),
            (90, 90, -5, 0), (270, 90, 5, 0), (0, 90, 0, 5), (180, 90, 0, -5),
            (360, 0, -5, 0)
        ]
        for (from, bearing, tail, right) in cases {
            let wind = CourseShotRecommendationInput.wind(speedMps: 5, fromDeg: from, bearingDeg: bearing)
            XCTAssertEqual(wind.tail, tail, accuracy: 1e-10)
            XCTAssertEqual(wind.right, right, accuracy: 1e-10)
        }
        let diagonal = CourseShotRecommendationInput.wind(speedMps: 5, fromDeg: 45, bearingDeg: 0)
        XCTAssertEqual(diagonal.tail, -5 / sqrt(2), accuracy: 1e-10)
        XCTAssertEqual(diagonal.right, -5 / sqrt(2), accuracy: 1e-10)
        XCTAssertEqual(hypot(diagonal.tail, diagonal.right), 5, accuracy: 1e-10)
    }

    func testNorthShotCardinalWindPhysicsAndTopDownSigns() throws {
        // Source only: no provider, predictor models or real settings needed.
        for (from, sign) in [(90.0, -1.0), (270.0, 1.0)] {
            let input = try XCTUnwrap(capture(weather: weather(direction: from)))
            XCTAssertEqual(input.bearingDeg, 0, accuracy: 1e-10)
            let launch = try XCTUnwrap(ClubRecommendationEngine.launches(
                profile: input.profile, conditions: input.conditions).first)
            XCTAssertEqual(launch.shot.windYMps, sign * 5, accuracy: 1e-10)
            XCTAssertEqual(launch.shot.windXMps, 0, accuracy: 1e-10)
            XCTAssertEqual(launch.shot.spinAxisDeg, 0) // Isolate wind, not intrinsic curvature.
            let flight = FlightSimulator.simulateShot(launch.shot)
            let lateral = try XCTUnwrap(flight.lateralCarryM)
            XCTAssertGreaterThan(sign * lateral, 0)
            let position = TrajectoryChartGeometry.topDown(
                downrange: try XCTUnwrap(flight.downrangeM), lateral: lateral)
            XCTAssertEqual(position.x, lateral) // Ascending chart x: west left, east right.
            XCTAssertGreaterThan(position.y, 0) // Ascending chart y: forward up.
            XCTAssertEqual(TrajectoryChartGeometry.windRotation(
                tail: input.conditions.tailwindMps, right: input.conditions.crosswindMps), sign * 90, accuracy: 1e-10)
        }
    }

    func testTopDownAxesAndTargetAreNotRotatedOrMirrored() {
        let right = TrajectoryChartGeometry.topDown(downrange: 100, lateral: 12)
        let left = TrajectoryChartGeometry.topDown(downrange: 100, lateral: -12)
        let target = TrajectoryChartGeometry.topDown(downrange: 150, lateral: 0)
        XCTAssertEqual(right.x, 12)
        XCTAssertEqual(left.x, -12)
        XCTAssertEqual(right.y, 100)
        XCTAssertEqual(left.y, 100)
        XCTAssertEqual(target.x, 0)
        XCTAssertEqual(target.y, 150)
        XCTAssertEqual(TrajectoryChartGeometry.windRotation(tail: 5, right: 0), 0)
        XCTAssertEqual(abs(TrajectoryChartGeometry.windRotation(tail: -5, right: 0)), 180)
    }

    func testPressureIsNotSeaLevelOrAltitudeCompensatedTwice() throws {
        let input = try XCTUnwrap(capture())
        XCTAssertEqual(input.conditions.pressureInputMode, .pressure)
        XCTAssertEqual(try input.conditions.effectivePressureHpa(), 900)
        XCTAssertEqual(input.conditions.siteElevationM, 400)
        XCTAssertEqual(input.conditions.elevationDeltaM, 10)
        XCTAssertEqual(input.conditions.tailwindMps, -5, accuracy: 1e-8)
        XCTAssertEqual(input.distanceM, GolfGeometry.distance(origin, target), accuracy: 1e-8)
        let shifted = try XCTUnwrap(capture(terrain: terrain(originHeight: 1400, targetHeight: 1410)))
        let launches = try ClubRecommendationEngine.launches(profile: input.profile, conditions: input.conditions)
        let shiftedLaunches = try ClubRecommendationEngine.launches(profile: shifted.profile, conditions: shifted.conditions)
        XCTAssertEqual(launches.first?.shot.pressureHpa, 900)
        XCTAssertEqual(shiftedLaunches.first?.shot.pressureHpa, 900)
        XCTAssertEqual(shiftedLaunches.first?.shot.targetElevationDeltaM, 10)
        XCTAssertEqual(launches.first?.shot.windXMps, -5)
        let density = Atmosphere.moistAirDensityKgM3(temperatureC: 15, pressureHpa: 900, relativeHumidityPct: 60)
        let vapor = 0.6 * Atmosphere.saturationVaporPressurePa(temperatureC: 15)
        let expected = (90_000 - vapor) / (GolfConstants.rDryAir * 288.15)
            + vapor / (GolfConstants.rWaterVapor * 288.15)
        XCTAssertEqual(density, expected, accuracy: 1e-12)
    }

    func testMissingOrStaleInputsCannotProduceSnapshot() throws {
        XCTAssertNil(capture(weather: weather(pressure: nil))) // Never substitute pressure_msl.
        XCTAssertNil(capture(weather: weather(direction: nil)))
        XCTAssertNil(capture(selected: GeoPoint(lat: target.lat + 0.001, lon: target.lon)))
        XCTAssertEqual(capture(liveOrigin: GeoPoint(lat: origin.lat + 0.001, lon: origin.lon)), capture())
        let unconfiguredDefaults = try XCTUnwrap(capture(profile: TrajectoryPlayerProfile()))
        XCTAssertTrue(unconfiguredDefaults.profile.isSetupComplete)
        XCTAssertEqual(unconfiguredDefaults.profile.detailLevel, .easy)
        XCTAssertEqual(unconfiguredDefaults.profile.availableClubs, TrajectoryGolfClub.standardBag)
        let emptyBagDefaults = try XCTUnwrap(capture(profile: TrajectoryPlayerProfile(isSetupComplete: true, availableClubs: [])))
        XCTAssertEqual(emptyBagDefaults.profile.detailLevel, .easy)
        XCTAssertEqual(emptyBagDefaults.profile.availableClubs, TrajectoryGolfClub.standardBag)
        let missing = TerrainProfile(samples: [TerrainSample(distanceMeters: 0, point: origin, elevationMeters: nil),
            TerrainSample(distanceMeters: 160, point: target, elevationMeters: 410)], isStraightLine: true)
        XCTAssertNil(capture(terrain: missing))
        let wrongEndpoints = TerrainProfile(samples: [TerrainSample(distanceMeters: 0, point: target, elevationMeters: 400),
            TerrainSample(distanceMeters: 160, point: origin, elevationMeters: 410)], isStraightLine: true)
        XCTAssertNil(capture(terrain: wrongEndpoints))
        XCTAssertNil(CourseShotRecommendationInput.capture(request: request(), selectedTarget: nil,
            liveOrigin: origin, usesGPS: true, weather: weather(), weatherLocation: origin,
            shotProfile: terrain(), profile: TrajectoryPlayerProfile(isSetupComplete: true)))
        XCTAssertEqual(CourseShotRecommendationInput.capture(request: request(), selectedTarget: target,
            liveOrigin: origin, usesGPS: false, weather: weather(), weatherLocation: origin,
            shotProfile: terrain(), profile: TrajectoryPlayerProfile(isSetupComplete: true))?.request.usesGPS, true)
    }

    func testDetailedProfilesRequireAnApplicableCalibrationAnchor() {
        var medium = TrajectoryPlayerProfile(isSetupComplete: true, detailLevel: .medium)
        XCTAssertNotNil(CourseShotRecommendationInput.profileIssue(medium))
        medium.setOverride(ClubLaunchOverride(carryDistanceM: 150), for: .sevenIron)
        XCTAssertNil(CourseShotRecommendationInput.profileIssue(medium))
        var expert = TrajectoryPlayerProfile(isSetupComplete: true, detailLevel: .expert)
        XCTAssertNotNil(CourseShotRecommendationInput.profileIssue(expert))
        expert.setOverride(ClubLaunchOverride(ballSpeedMps: 45, launchAngleDeg: 17, spinRateRpm: 6000), for: .sevenIron)
        XCTAssertNil(CourseShotRecommendationInput.profileIssue(expert))
    }

    func testTeeFallbackAndChangedWeatherAreCapturedNotMislabelled() throws {
        let original = try XCTUnwrap(capture())
        let changed = try XCTUnwrap(capture(weather: weather(pressure: 950)))
        XCTAssertNotEqual(original, changed)
        let teeRequest = TerrainRequest(courseID: "offline-fixture", holeNumber: 1, path: [origin, target], flag: target,
                                       origin: origin, target: target, usesPointOnlyGeometry: true, usesGPS: false)
        let teeInput = try XCTUnwrap(CourseShotRecommendationInput.capture(request: teeRequest, selectedTarget: target,
            liveOrigin: origin, usesGPS: false, weather: weather(), weatherLocation: origin,
            shotProfile: terrain(), profile: original.profile))
        XCTAssertFalse(teeInput.request.usesGPS)
        XCTAssertEqual(teeInput.distanceM, original.distanceM)
        // A read-only weather accessor has no acquisition side effect.
        let weatherStore = CourseWeatherStore()
        XCTAssertNil(weatherStore.weather(for: origin))
        XCTAssertFalse(weatherStore.isLoading)
    }

    func testCancelledEvaluationCannotReturnOldRecommendations() async throws {
        let input = try XCTUnwrap(capture())
        let launches = try ClubRecommendationEngine.launches(profile: input.profile, conditions: input.conditions)
        let engine = ClubRecommendationEngine()
        let task = Task { try await engine.recommend(for: input.distanceM, launches: launches) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled generation must not publish recommendations")
        } catch is CancellationError { }
    }

    func testSharedEngineMatchesPredictorAndDoesNotChangePractice() async throws {
        let suite = "course-shot-offline-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profileStore = PlayerProfileStore(userDefaults: defaults, storageKey: "offline.profile")
        profileStore.profile = TrajectoryPlayerProfile(isSetupComplete: true, availableClubs: [.sevenIron, .eightIron, .nineIron])
        let model = TrajectoryCalculatorViewModel(playerProfileStore: profileStore, userDefaults: defaults)
        model.activeClub = .eightIron
        model.temperatureC = 27
        model.tailwindMps = 2
        model.crosswindMps = -3
        model.elevationDeltaM = -7
        let beforeConditions = defaults.data(forKey: "trajectory.lastConditions")
        let beforeProfile = profileStore.profile
        let beforeBallSpeed = model.ballSpeedMps
        let input = try XCTUnwrap(capture(profile: beforeProfile))
        let launches = try ClubRecommendationEngine.launches(profile: beforeProfile, conditions: input.conditions)
        let engine = ClubRecommendationEngine()
        let map = try await engine.recommend(for: input.distanceM, launches: launches)
        let practice = try await model.recommendClub(for: input.distanceM, conditions: input.conditions)
        XCTAssertEqual(map.map(\.club), practice.map(\.club))
        XCTAssertEqual(map.count, 3)
        let predictor = try HybridPredictor()
        for option in map {
            let shot = try XCTUnwrap(launches.first { $0.club == option.club }?.shot)
            let prediction = try predictor.predict(shot)
            XCTAssertEqual(option.estimatedCarryM, try XCTUnwrap(prediction.hybrid["carry_m"]), accuracy: 1e-10)
            XCTAssertEqual(option.differenceM, abs(option.estimatedCarryM - input.distanceM), accuracy: 1e-10)
            XCTAssertEqual(option.trajectory.xM, prediction.physics.trajectory.xM)
        }
        XCTAssertEqual(map.map(\.differenceM), map.map(\.differenceM).sorted())
        XCTAssertEqual(model.activeClub, .eightIron)
        XCTAssertEqual(model.ballSpeedMps, beforeBallSpeed)
        XCTAssertEqual(model.temperatureC, 27)
        XCTAssertEqual(model.tailwindMps, 2)
        XCTAssertEqual(model.crosswindMps, -3)
        XCTAssertEqual(model.elevationDeltaM, -7)
        XCTAssertEqual(profileStore.profile, beforeProfile)
        XCTAssertEqual(defaults.data(forKey: "trajectory.lastConditions"), beforeConditions)
        XCTAssertNil(model.prediction)
    }

    func testUnreachableElevationIsAnErrorNotAYardageFallback() async throws {
        var input = try XCTUnwrap(capture()).conditions
        input.elevationDeltaM = 500
        let profile = TrajectoryPlayerProfile(isSetupComplete: true, availableClubs: [.sevenIron])
        let launches = try ClubRecommendationEngine.launches(profile: profile, conditions: input)
        do {
            _ = try await ClubRecommendationEngine().recommend(for: 150, launches: launches)
            XCTFail("Unreachable terrain elevation must not invent a recommendation")
        } catch HybridPredictorError.noClubCanReachTargetElevation { }
    }
}