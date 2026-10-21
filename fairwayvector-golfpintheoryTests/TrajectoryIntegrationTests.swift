import Testing
import UIKit
@testable import fairwayvector_golfpintheory

struct TrajectoryIntegrationTests {
    @Test func trajectoryArtworkIsBundled() {
        let imageNames = [
            "ballspeed", "driver", "elevation", "fairwaywood", "homescreen", "humidity",
            "hybrid", "iron", "launchangle", "launchdirection", "pressure", "spinaxis",
            "spinrate", "temperature", "wedge", "wind"
        ]

        for name in imageNames {
            #expect(UIImage(named: name) != nil, "Missing Trajectory image: \(name)")
        }
    }

    @Test func bundledModelsPredictShot() throws {
        let predictor = try HybridPredictor()
        let shot = ShotInputs(
            ballSpeedMps: Units.mpsFromMph(150),
            launchAngleDeg: 12,
            launchDirectionDeg: 0,
            spinRateRpm: 2700,
            spinAxisDeg: 0
        )

        let prediction = try predictor.predict(shot)
        #expect((prediction.hybrid["carry_m"] ?? 0) > 0)
        #expect((prediction.hybrid["apex_m"] ?? 0) > 0)
    }
}