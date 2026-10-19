#if DEBUG
import XCTest
@testable import fairwayvector_pintheory

/// Offline regression SOURCE only; no GPS manager, provider, real settings or predictor.
@MainActor
final class DevelopmentScoringPositionTests: XCTestCase {
    private func personalPlan() -> ScoringShotPlan {
        var wedge = Wedge(name: "PW", fullCarry: 120)
        wedge.setCarry(120, for: .stock, swing: .full)
        return ScoringShotPlan.make(profile: TrajectoryPlayerProfile(isSetupComplete: true), wedges: [wedge])
    }

    func testMeasuredDistanceAlwaysFitsSamePersonalScoringThreshold() throws {
        let plan = personalPlan()
        XCTAssertEqual(try XCTUnwrap(plan.maxFullCarryM), 120 * 0.9144, accuracy: 1e-9)
        for target in [GeoPoint(lat: 57.62, lon: 12), GeoPoint(lat: -33.9, lon: 18.4),
                       GeoPoint(lat: 0, lon: 179.9999), GeoPoint(lat: 80, lon: -179.9999)] {
            let tee = GolfGeometry.destination(from: target, distanceM: 350, bearingDeg: 280)
            for fraction in [0.0, 0.25, 0.5, 1.0] {
                for jitter in [-20.0, 0, 20] {
                    let point = try XCTUnwrap(DevelopmentScoringPosition.make(plan: plan, target: target,
                        tee: tee, fraction: fraction, jitterDeg: jitter))
                    let distance = GolfGeometry.distance(point, target)
                    XCTAssertTrue(TerrainGeometry.valid(point))
                    XCTAssertGreaterThan(distance, 0.1)
                    XCTAssertLessThanOrEqual(distance, try XCTUnwrap(plan.maxFullCarryM) * 0.99)
                    XCTAssertTrue(plan.isScoring(distanceM: distance))
                    let bearing = GolfGeometry.bearing(from: target, to: point)
                    let expected = GolfGeometry.bearing(from: target, to: tee) + jitter
                    let difference = (bearing - expected + 540).truncatingRemainder(dividingBy: 360) - 180
                    XCTAssertEqual(difference, 0, accuracy: 1e-5)
                }
            }
        }
    }

    func testShortRangeAndNearTeeCannotConstructInvalidRandomRange() throws {
        let target = GeoPoint(lat: 57.62, lon: 12)
        let tee = GolfGeometry.destination(from: target, distanceM: 0.3, bearingDeg: 0)
        let plan = ScoringShotPlan(shots: [], maxFullCarryM: 0.3, guidance: "fixture")
        let range = try XCTUnwrap(DevelopmentScoringPosition.distanceRange(plan: plan, target: target, tee: tee))
        XCTAssertEqual(range.lowerBound, range.upperBound)
        let point = try XCTUnwrap(DevelopmentScoringPosition.make(plan: plan, target: target,
            tee: tee, fraction: 1, jitterDeg: 0))
        XCTAssertGreaterThan(GolfGeometry.distance(point, target), 0.1)
        XCTAssertTrue(plan.isScoring(distanceM: GolfGeometry.distance(point, target)))
        for threshold in [0.0, -1, 0.1, Double.nan, Double.infinity] {
            let invalid = ScoringShotPlan(shots: [], maxFullCarryM: threshold, guidance: "fixture")
            XCTAssertNil(DevelopmentScoringPosition.distanceRange(plan: invalid, target: target, tee: tee))
        }
        XCTAssertNil(DevelopmentScoringPosition.make(plan: personalPlan(), target: target,
            tee: target, fraction: 0, jitterDeg: 0))
        XCTAssertNil(DevelopmentScoringPosition.make(plan: personalPlan(), target: target,
            tee: tee, fraction: .nan, jitterDeg: 0))
    }

    func testMissingDefaultsAndLegacyCarriesNeverEnableSimulation() {
        let profile = TrajectoryPlayerProfile(isSetupComplete: true)
        let target = GeoPoint(lat: 57.62, lon: 12)
        let tee = GolfGeometry.destination(from: target, distanceM: 300, bearingDeg: 180)
        for wedges in [[], Wedge.defaults, [Wedge(name: "PW", fullCarry: 120)]] {
            let plan = ScoringShotPlan.make(profile: profile, wedges: wedges)
            XCTAssertNil(plan.maxFullCarryM)
            XCTAssertNil(DevelopmentScoringPosition.make(plan: plan, target: target, tee: tee, fraction: 0.5, jitterDeg: 0))
        }
    }

    func testCapturedSimulationIsNotGPSOrTeeAndSurvivesNewLiveFix() throws {
        let target = GeoPoint(lat: 57.62, lon: 12)
        let tee = GolfGeometry.destination(from: target, distanceM: 350, bearingDeg: 180)
        var wedge = Wedge(name: "PW", fullCarry: 120)
        wedge.setCarry(120, for: .stock, swing: .full)
        let profile = TrajectoryPlayerProfile(isSetupComplete: true)
        let point = try XCTUnwrap(DevelopmentScoringPosition.make(plan: personalPlan(), target: target,
            tee: tee, fraction: 0.5, jitterDeg: 10))
        let origin = DistanceOrigin(point: point, source: .simulated)
        XCTAssertFalse(origin.usesGPS)
        XCTAssertTrue(origin.isSimulated)
        let request = TerrainRequest(courseID: "offline-simulation", holeNumber: 1, path: [tee, target],
            flag: target, origin: origin.point, target: target, usesPointOnlyGeometry: true,
            usesGPS: origin.usesGPS, isSimulatedOrigin: origin.isSimulated)
        XCTAssertEqual(request.originLabel, "Simulated golfer · Development")
        let terrain = TerrainProfile(samples: [TerrainSample(distanceMeters: 0, point: point, elevationMeters: 100),
            TerrainSample(distanceMeters: GolfGeometry.distance(point, target), point: target, elevationMeters: 101)],
            isStraightLine: true)
        let weather = CourseWeather(elevationMeters: 100, timezone: "UTC", observedAt: "fixture",
            temperatureC: 20, relativeHumidityPercent: 50, surfacePressureHpa: 1013.25,
            seaLevelPressureHpa: 1013.25, windSpeedMps: 0, windDirectionDegrees: 0, windGustsMps: 0)
        let captured = try XCTUnwrap(CourseShotRecommendationInput.capture(request: request, selectedTarget: target,
            weather: weather, weatherLocation: target, shotProfile: terrain, profile: profile, wedges: [wedge]))
        XCTAssertTrue(captured.isScoring)
        XCTAssertFalse(captured.request.usesGPS)
        XCTAssertTrue(captured.request.isSimulatedOrigin)
        XCTAssertEqual(captured, CourseShotRecommendationInput.capture(request: request, selectedTarget: target,
            liveOrigin: tee, usesGPS: true, weather: weather, weatherLocation: target,
            shotProfile: terrain, profile: profile, wedges: [wedge]))
    }
}
#endif