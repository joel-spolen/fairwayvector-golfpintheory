import Foundation

nonisolated enum HybridPredictorError: Error, LocalizedError {
    case missingResource(String)
    case invalidManifest(String)
    case nonFiniteOutput(String)
    case targetElevationExceedsApex(targetM: Double, apexM: Double)
    case noClubCanReachTargetElevation(targetM: Double, highestApexM: Double)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Missing bundled ML resource: \(name)"
        case .invalidManifest(let reason):
            return "Bundled ML manifest is invalid: \(reason)"
        case .nonFiniteOutput(let reason):
            return "Prediction produced a non-finite value: \(reason)"
        case .targetElevationExceedsApex(let targetM, let apexM):
            return String(format: "The target is %.1f m above the launch point, but this shot peaks at %.1f m. Lower the elevation change or increase the launch conditions.", targetM, apexM)
        case .noClubCanReachTargetElevation(let targetM, let highestApexM):
            return String(format: "No club reaches the target elevation of %.1f m. The highest simulated peak is %.1f m. Lower the elevation change or adjust the launch conditions.", targetM, highestApexM)
        }
    }
}

/// Physics-only, ML-correction, and final hybrid scalar outputs for one shot.
nonisolated struct HybridPrediction: Sendable {
    var physics: FlightResult
    var corrections: [String: Double]
    var hybrid: [String: Double]
}

/// Frozen feature order for the HGB residual models. Must match `CONTINUOUS_FEATURES`
/// in `validate_v11_ml_features.py` exactly.
nonisolated private let continuousFeatures = [
    "ball_speed_mps",
    "launch_angle_deg",
    "launch_direction_deg",
    "spin_rate_rpm",
    "spin_axis_deg",
    "initial_spin_factor",
    "initial_reynolds",
    "temperature_c",
    "pressure_hpa",
    "humidity_pct",
    "wind_x_mps",
    "wind_y_mps",
    "wind_z_mps",
    "v11_sim_carry_m",
    "v11_sim_apex_m",
    "v11_sim_flight_time_s",
    "v11_sim_landing_angle_deg",
    "v11_sim_landing_speed_mps",
]

/// Runtime port of `hybrid_v11_ml.py`: Physics V1.1 followed by five HGB residual corrections.
nonisolated final class HybridPredictor: Sendable {
    private let models: [String: HGBModel]
    private static let dtS = 0.01
    private static let spinDecayPerS = 0.0

    /// target key -> output name, matching `MODEL_OUTPUT_COLUMNS` in `hybrid_v11_ml.py`.
    private static let targetOutputNames: [(target: String, exportName: String, output: String)] = [
        ("ml_target_carry_m", "carry", "carry_m"),
        ("ml_target_apex_m", "apex", "apex_m"),
        ("ml_target_flight_time_s", "flight_time", "flight_time_s"),
        ("ml_target_landing_angle_deg", "landing_angle", "landing_angle_deg"),
        ("ml_target_landing_speed_mps", "landing_speed", "landing_speed_mps"),
    ]

    init(bundle: Bundle = .main) throws {
        try Self.validateManifest(bundle: bundle)

        var loaded: [String: HGBModel] = [:]
        for entry in Self.targetOutputNames {
            let model = try HGBModelLoader.load(exportName: entry.exportName, bundle: bundle)
            guard model.featureList == continuousFeatures else {
                throw HybridPredictorError.invalidManifest("\(entry.exportName) feature order mismatch")
            }
            loaded[entry.target] = model
        }
        models = loaded
    }

    private static func validateManifest(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "MLModels")
            ?? bundle.url(forResource: "manifest", withExtension: "json") else {
            throw HybridPredictorError.missingResource("manifest.json")
        }
        let data = try Data(contentsOf: url)
        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HybridPredictorError.invalidManifest("manifest.json is not a JSON object")
        }
        guard manifest["hybridModelVersion"] as? String == "Physics V1.1 + HGB residual v1" else {
            throw HybridPredictorError.invalidManifest("unexpected hybridModelVersion")
        }
        guard manifest["physicsVersion"] as? String == PhysicsV11Constants.version else {
            throw HybridPredictorError.invalidManifest("unexpected physicsVersion")
        }
        guard manifest["mlModelType"] as? String == "HistGradientBoostingRegressor" else {
            throw HybridPredictorError.invalidManifest("unexpected mlModelType")
        }
        guard manifest["featureList"] as? [String] == continuousFeatures else {
            throw HybridPredictorError.invalidManifest("unexpected featureList")
        }
    }

    private func initialAeroFeatures(shot: ShotInputs) -> (spinFactor: Double, reynolds: Double) {
        let omegaRadS = shot.spinRateRpm * (2.0 * Double.pi / 60.0)
        let spinFactor = GolfConstants.ballRadiusM * abs(omegaRadS) / shot.ballSpeedMps
        let airDensity = Atmosphere.moistAirDensityKgM3(
            temperatureC: shot.temperatureC,
            pressureHpa: shot.pressureHpa,
            relativeHumidityPct: shot.relativeHumidityPct
        )
        let reynolds = airDensity * shot.ballSpeedMps * GolfConstants.ballDiameterM
            / Atmosphere.dynamicViscosityAirPaS(temperatureC: shot.temperatureC)
        return (spinFactor, reynolds)
    }

    private func buildFeatureVector(shot: ShotInputs, physics: FlightResult) throws -> [Double] {
        guard let carry = physics.actualTerrainCarryM,
              let flightTime = physics.flightTimeS,
              let landingAngle = physics.landingAngleDeg,
              let landingSpeed = physics.landingSpeedMps
        else {
            throw HybridPredictorError.nonFiniteOutput("Physics V1.1 simulation did not land")
        }
        let (spinFactor, reynolds) = initialAeroFeatures(shot: shot)

        let values: [String: Double] = [
            "ball_speed_mps": shot.ballSpeedMps,
            "launch_angle_deg": shot.launchAngleDeg,
            "launch_direction_deg": shot.launchDirectionDeg,
            "spin_rate_rpm": shot.spinRateRpm,
            "spin_axis_deg": shot.spinAxisDeg,
            "initial_spin_factor": spinFactor,
            "initial_reynolds": reynolds,
            "temperature_c": shot.temperatureC,
            "pressure_hpa": shot.pressureHpa,
            "humidity_pct": shot.relativeHumidityPct,
            "wind_x_mps": shot.windXMps,
            "wind_y_mps": shot.windYMps,
            "wind_z_mps": shot.windZMps,
            "v11_sim_carry_m": carry,
            "v11_sim_apex_m": physics.apexHeightM,
            "v11_sim_flight_time_s": flightTime,
            "v11_sim_landing_angle_deg": landingAngle,
            "v11_sim_landing_speed_mps": landingSpeed,
        ]
        let vector = try continuousFeatures.map { name -> Double in
            guard let value = values[name] else {
                throw HybridPredictorError.invalidManifest("missing feature value for \(name)")
            }
            return value
        }
        guard vector.allSatisfy({ $0.isFinite }) else {
            throw HybridPredictorError.nonFiniteOutput("feature vector contains non-finite values")
        }
        return vector
    }

    /// Runs Physics V1.1, applies the five residual corrections, and returns all outputs.
    func predict(_ shot: ShotInputs) throws -> HybridPrediction {
        let physics = FlightSimulator.simulateShot(
            shot,
            aero: PhysicsV11AeroModel(),
            dtS: Self.dtS,
            spinDecayPerS: Self.spinDecayPerS
        )
        guard physics.landed else {
            if shot.targetElevationDeltaM >= physics.apexHeightM {
                throw HybridPredictorError.targetElevationExceedsApex(
                    targetM: shot.targetElevationDeltaM,
                    apexM: physics.apexHeightM
                )
            }
            throw HybridPredictorError.nonFiniteOutput("Physics V1.1 simulation did not land")
        }

        let features = try buildFeatureVector(shot: shot, physics: physics)

        // Already validated non-nil by the `physics.landed` guard above.
        guard let carryM = physics.actualTerrainCarryM,
              let flightTimeS = physics.flightTimeS,
              let landingAngleDeg = physics.landingAngleDeg,
              let landingSpeedMps = physics.landingSpeedMps
        else {
            throw HybridPredictorError.nonFiniteOutput("Physics V1.1 simulation did not land")
        }

        var corrections: [String: Double] = [:]
        var hybrid: [String: Double] = [:]
        let physicsOutputs: [String: Double] = [
            "carry_m": carryM,
            "apex_m": physics.apexHeightM,
            "flight_time_s": flightTimeS,
            "landing_angle_deg": landingAngleDeg,
            "landing_speed_mps": landingSpeedMps,
        ]

        for entry in Self.targetOutputNames {
            guard let model = models[entry.target] else {
                throw HybridPredictorError.invalidManifest("missing loaded model for \(entry.target)")
            }
            let correction = model.predict(features: features)
            guard correction.isFinite else {
                throw HybridPredictorError.nonFiniteOutput("correction for \(entry.output)")
            }
            guard let baseline = physicsOutputs[entry.output] else {
                throw HybridPredictorError.invalidManifest("missing physics output for \(entry.output)")
            }
            corrections[entry.output] = correction
            hybrid[entry.output] = baseline + correction
        }

        return HybridPrediction(physics: physics, corrections: corrections, hybrid: hybrid)
    }
}
