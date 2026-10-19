import XCTest
@testable import fairwayvector_pintheory

/// Offline regression SOURCE. Compile only; no app launch, provider transport,
/// real preferences, weather acquisition, live caches or paid-provider ledger.
@MainActor
final class ScoringRecommendationTests: XCTestCase {
    private func profile() -> TrajectoryPlayerProfile {
        TrajectoryPlayerProfile(isSetupComplete: true, availableClubs: [.driver, .pitchingWedge, .sandWedge])
    }

    private func wedge(name: String = "PW", yards: Double = 120) -> Wedge {
        let id = UUID(uuidString: name == "PW" ? "00000000-0000-0000-0000-000000000001" : "00000000-0000-0000-0000-000000000002")!
        var wedge = Wedge(id: id, name: name, fullCarry: yards)
        wedge.setCarry(yards, for: .stock, swing: .full)
        return wedge
    }

    func testInclusivePersonalBoundaryNotGPSOrWeatherThreshold() throws {
        let plan = ScoringShotPlan.make(profile: profile(), wedges: [wedge(), wedge(name: "54", yards: 90)])
        let maximum = try XCTUnwrap(plan.maxFullCarryM)
        XCTAssertEqual(maximum, 120 * 0.9144, accuracy: 1e-10)
        XCTAssertTrue(plan.isScoring(distanceM: maximum))
        XCTAssertTrue(plan.isScoring(distanceM: maximum - 0.001))
        XCTAssertFalse(plan.isScoring(distanceM: maximum + 0.001))
        XCTAssertFalse(plan.isScoring(distanceM: 400))
        XCTAssertFalse(plan.isScoring(distanceM: 0))
        XCTAssertFalse(plan.isScoring(distanceM: .nan))
        XCTAssertFalse(plan.isScoring(distanceM: .infinity))
    }

    func testNineDistinctCombinationsPerWedgeAndActualMatrixFactors() throws {
        var pw = wedge()
        pw.setCarry(41, for: .high, swing: .half)
        let plan = ScoringShotPlan.make(profile: profile(), wedges: [pw, wedge(name: "54", yards: 90)])
        XCTAssertEqual(plan.shots.count, 18)
        XCTAssertEqual(Set(plan.shots.map(\.id)).count, 18)
        let pwShots = plan.shots.filter { $0.club == .pitchingWedge }
        XCTAssertEqual(pwShots.count, 9)
        for trajectory in ["Low", "Mid", "High"] {
            for strength in ["50%", "75%", "100%"] {
                XCTAssertEqual(pwShots.filter { $0.title == "PW · \(trajectory) · \(strength)" }.count, 1)
            }
        }
        let half = try XCTUnwrap(pwShots.first { $0.title == "PW · Mid · 50%" })
        let partial = try XCTUnwrap(pwShots.first { $0.title == "PW · Mid · 75%" })
        let high = try XCTUnwrap(pwShots.first { $0.title == "PW · High · 50%" })
        XCTAssertEqual(half.nominalCarryM, 120 * 0.70 * 0.9144, accuracy: 1e-10)
        XCTAssertEqual(partial.nominalCarryM, 120 * 0.90 * 0.9144, accuracy: 1e-10)
        XCTAssertEqual(high.nominalCarryM, 41 * 0.9144, accuracy: 1e-10)
        XCTAssertTrue(high.source.contains("Entered Wedge Matrix cell"))
        XCTAssertTrue(half.source.contains("estimated cell"))
        XCTAssertTrue(half.source.contains("not measured partial-shot data"))
        let baseline = ClubProfileDefaults.effectiveProfile(for: .pitchingWedge, playerProfile: profile())
        XCTAssertEqual(half.spinRateRpm, baseline.spinRateRpm.value)
        XCTAssertEqual(half.launchAngleDeg, baseline.launchAngleDeg.value)
    }

    func testUntouchedDefaultsAndLegacyUnverifiedCarryNeverInventRange() throws {
        let defaults = ScoringShotPlan.make(profile: profile(), wedges: Wedge.defaults)
        XCTAssertNil(defaults.maxFullCarryM)
        XCTAssertTrue(defaults.shots.isEmpty)
        XCTAssertFalse(defaults.guidance.isEmpty)
        // Legacy fullCarry without a cell override/provenance cannot distinguish
        // an old add-club value from a stock default. Require explicit re-entry.
        let data = Data("{\"name\":\"PW\",\"fullCarry\":150,\"isInBag\":true}".utf8)
        let legacy = try JSONDecoder().decode(Wedge.self, from: data)
        XCTAssertFalse(legacy.fullCarryUserProvided)
        XCTAssertNil(ScoringShotPlan.make(profile: profile(), wedges: [legacy]).maxFullCarryM)
        let restored = try JSONDecoder().decode(Wedge.self, from: JSONEncoder().encode(wedge()))
        XCTAssertEqual(ScoringShotPlan.make(profile: profile(), wedges: [restored]).shots.count, 9)
        let added = Wedge(name: "52", fullCarry: 102, fullCarryUserProvided: true)
        XCTAssertEqual(ScoringShotPlan.make(profile: profile(), wedges: [added]).maxFullCarryM,
                       102 * 0.9144)
    }

    func testEffectivePracticeCalibrationFallbackAndOutOfBagAuthority() throws {
        var profile = TrajectoryPlayerProfile(isSetupComplete: true, detailLevel: .medium,
            availableClubs: [.driver, .pitchingWedge])
        profile.setOverride(ClubLaunchOverride(carryDistanceM: 88), for: .pitchingWedge)
        let plan = ScoringShotPlan.make(profile: profile, wedges: [Wedge.defaults[0]])
        XCTAssertEqual(plan.maxFullCarryM, 88)
        XCTAssertEqual(plan.shots.count, 9)
        XCTAssertTrue(plan.shots.allSatisfy { $0.source.contains("Effective user-calibrated Practice") })
        var excluded = wedge()
        excluded.isInBag = false
        XCTAssertNil(ScoringShotPlan.make(profile: profile, wedges: [excluded]).maxFullCarryM)
        // Matrix cell carries take precedence over a matching Practice nominal.
        XCTAssertEqual(ScoringShotPlan.make(profile: profile, wedges: [wedge()]).maxFullCarryM, 120 * 0.9144)
        var partialOnly = Wedge(name: "54", fullCarry: 90)
        partialOnly.setCarry(32, for: .stock, swing: .half)
        XCTAssertNil(ScoringShotPlan.make(profile: self.profile(), wedges: [partialOnly]).maxFullCarryM)
    }

    func testUnknownLoftInvalidCellAndOversizeBagFailExplicitly() {
        let unknown = ScoringShotPlan.make(profile: profile(), wedges: [wedge(name: "My custom wedge")])
        XCTAssertNil(unknown.maxFullCarryM)
        XCTAssertTrue(unknown.guidance.contains("unknown loft"))
        var invalid = wedge()
        invalid.setCarry(-10, for: .high, swing: .half)
        let invalidPlan = ScoringShotPlan.make(profile: profile(), wedges: [invalid])
        XCTAssertTrue(invalidPlan.shots.isEmpty)
        XCTAssertTrue(invalidPlan.guidance.contains("invalid carry cells"))
        let large = ScoringShotPlan.make(profile: profile(), wedges: (0..<15).map { _ in
            var value = wedge()
            value.id = UUID()
            return value
        })
        XCTAssertTrue(large.shots.isEmpty)
        XCTAssertNil(large.maxFullCarryM)
        XCTAssertTrue(large.guidance.contains("at most 14"))
    }

    private func input(gps: Bool, latOffset: Double = 0.0006, wedges: [Wedge]? = nil,
                       liveOrigin: GeoPoint? = nil) throws -> CourseShotRecommendationInput {
        let origin = GeoPoint(lat: 57.62, lon: 12)
        let target = GeoPoint(lat: origin.lat + latOffset, lon: origin.lon)
        let request = TerrainRequest(courseID: "scoring-offline", holeNumber: 1, path: [origin, target], flag: target,
            origin: origin, target: target, usesPointOnlyGeometry: true, usesGPS: gps)
        let weather = CourseWeather(elevationMeters: 1234, timezone: "UTC", observedAt: "2026-10-05T10:00",
            temperatureC: 15, relativeHumidityPercent: 60, surfacePressureHpa: 900,
            seaLevelPressureHpa: 1015, windSpeedMps: 5, windDirectionDegrees: 90, windGustsMps: 12)
        let terrain = TerrainProfile(samples: [TerrainSample(distanceMeters: 0, point: origin, elevationMeters: 400),
            TerrainSample(distanceMeters: GolfGeometry.distance(origin, target), point: target, elevationMeters: 403)],
            isStraightLine: true)
        return try XCTUnwrap(CourseShotRecommendationInput.capture(request: request, selectedTarget: target,
            liveOrigin: liveOrigin, usesGPS: !gps, weather: weather, weatherLocation: origin, shotProfile: terrain,
            profile: profile(), wedges: wedges ?? [wedge()]))
    }

    func testCommittedGPSTeeFallbackWeatherAndCalibrationSnapshot() throws {
        let gps = try input(gps: true)
        let tee = try input(gps: false)
        XCTAssertTrue(gps.isScoring)
        XCTAssertTrue(tee.isScoring)
        XCTAssertTrue(gps.request.usesGPS)
        XCTAssertFalse(tee.request.usesGPS)
        XCTAssertEqual(gps.distanceM, tee.distanceM)
        let movedLiveGPS = try input(gps: true, liveOrigin: GeoPoint(lat: 58, lon: 13))
        XCTAssertEqual(gps, movedLiveGPS) // Capture remains committed, not live.
        XCTAssertFalse(try input(gps: true, latOffset: 0.004).isScoring) // GPS on at ~445m.
        XCTAssertEqual(gps.conditions.pressureInputMode, .pressure)
        XCTAssertEqual(try gps.conditions.effectivePressureHpa(), 900)
        XCTAssertEqual(gps.conditions.elevationDeltaM, 3)
        XCTAssertEqual(gps.conditions.tailwindMps, 0, accuracy: 1e-8)
        XCTAssertEqual(gps.conditions.crosswindMps, -5, accuracy: 1e-8)
        var edited = wedge()
        edited.setCarry(40, for: .stock, swing: .half)
        XCTAssertNotEqual(gps, try input(gps: true, wedges: [edited]))
    }

    func testInverseFitRankingAndNormalWeatherTerrainPipelineWithoutPracticeMutation() async throws {
        let input = try input(gps: true)
        let storeName = "scoring-source-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: storeName))
        defer { defaults.removePersistentDomain(forName: storeName) }
        let store = PlayerProfileStore(userDefaults: defaults, storageKey: "fixture.profile")
        store.profile = input.profile
        let model = TrajectoryCalculatorViewModel(playerProfileStore: store, userDefaults: defaults)
        model.activeClub = .driver
        model.temperatureC = 31
        model.tailwindMps = 7
        let speedBefore = model.ballSpeedMps
        let profileBefore = store.profile
        let engine = ScoringRecommendationEngine()
        let conditions = ShotInputs(ballSpeedMps: 1, launchAngleDeg: 1, launchDirectionDeg: 0,
            spinRateRpm: 0, spinAxisDeg: 0, temperatureC: input.conditions.temperatureC,
            pressureHpa: try input.conditions.effectivePressureHpa(), relativeHumidityPct: input.conditions.humidityPct,
            windXMps: input.conditions.tailwindMps, windYMps: input.conditions.crosswindMps,
            targetElevationDeltaM: input.conditions.elevationDeltaM)
        let evaluation = try await engine.recommend(targetM: input.distanceM,
            specs: input.scoringPlan.shots, conditions: conditions)
        XCTAssertEqual(evaluation.recommendations.count + evaluation.unavailable.count, 9)
        XCTAssertFalse(evaluation.recommendations.isEmpty)
        let errors = evaluation.recommendations.map { $0.recommendation.differenceM }
        XCTAssertEqual(errors, errors.sorted())
        XCTAssertEqual(Set(evaluation.recommendations.map(\.id)).count, evaluation.recommendations.count)
        let predictor = try HybridPredictor()
        for choice in evaluation.recommendations {
            let spec = try XCTUnwrap(choice.scoringShot)
            let reference = try await engine.referenceLaunch(for: spec)
            let referenceCarry = try XCTUnwrap(predictor.predict(reference).hybrid["carry_m"])
            XCTAssertEqual(referenceCarry, spec.nominalCarryM, accuracy: 0.5)
            // Half/three-quarter speed comes from inverse flight, not 0.5/0.75 scaling.
            let shot = try XCTUnwrap(choice.calibratedLaunch)
            XCTAssertEqual(shot.pressureHpa, 900)
            XCTAssertEqual(shot.temperatureC, 15)
            XCTAssertEqual(shot.relativeHumidityPct, 60)
            XCTAssertEqual(shot.windYMps, -5, accuracy: 1e-8)
            XCTAssertEqual(shot.targetElevationDeltaM, 3)
            let direct = try predictor.predict(shot)
            XCTAssertEqual(choice.recommendation.estimatedCarryM, try XCTUnwrap(direct.hybrid["carry_m"]), accuracy: 1e-9)
            XCTAssertEqual(choice.recommendation.trajectory.yM, direct.physics.trajectory.yM)
            XCTAssertEqual(choice.recommendation.targetElevationM, 3)
        }
        XCTAssertEqual(store.profile, profileBefore)
        XCTAssertEqual(model.activeClub, .driver)
        XCTAssertEqual(model.ballSpeedMps, speedBefore)
        XCTAssertEqual(model.temperatureC, 31)
        XCTAssertEqual(model.tailwindMps, 7)
    }

    func testCancellationAndUnreachableCombinationsAreNotFullBagFallback() async throws {
        let input = try input(gps: true)
        let engine = ScoringRecommendationEngine()
        var conditions = ShotInputs(ballSpeedMps: 1, launchAngleDeg: 1,
            launchDirectionDeg: 0, spinRateRpm: 0, spinAxisDeg: 0)
        conditions.targetElevationDeltaM = 1000
        let evaluation = try await engine.recommend(targetM: input.distanceM,
            specs: input.scoringPlan.shots, conditions: conditions)
        XCTAssertTrue(evaluation.recommendations.isEmpty)
        XCTAssertEqual(evaluation.unavailable.count, 9)
        let task = Task { try await engine.recommend(targetM: input.distanceM,
            specs: input.scoringPlan.shots, conditions: conditions) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled scoring generation must not return results")
        } catch is CancellationError { }
    }

    func testStableTiesAndBeyondRangeRetainsOrdinaryBag() async throws {
        let input = try input(gps: true)
        let spec = try XCTUnwrap(input.scoringPlan.shots.first { $0.title == "PW · Mid · 100%" })
        let duplicateShape = ScoringShotSpec(id: "second-shape", club: spec.club, title: "Second equal shape",
            nominalCarryM: spec.nominalCarryM, launchAngleDeg: spec.launchAngleDeg,
            spinRateRpm: spec.spinRateRpm, spinAxisDeg: spec.spinAxisDeg, source: spec.source)
        let conditions = ShotInputs(ballSpeedMps: 1, launchAngleDeg: 1, launchDirectionDeg: 0,
            spinRateRpm: 0, spinAxisDeg: 0)
        let engine = ScoringRecommendationEngine()
        let evaluation = try await engine.recommend(targetM: 100, specs: [spec, duplicateShape], conditions: conditions)
        XCTAssertEqual(evaluation.recommendations.map(\.id), [spec.id, duplicateShape.id])
        let distant = try self.input(gps: true, latOffset: 0.004)
        XCTAssertFalse(distant.isScoring)
        let ordinary = try ClubRecommendationEngine.launches(profile: distant.profile, conditions: distant.conditions)
        XCTAssertEqual(Set(ordinary.map(\.club)), distant.profile.availableClubs)
        XCTAssertTrue(ordinary.contains { $0.club == .driver })
    }
}