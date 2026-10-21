import Foundation

/// Replaceable Cd/Cl calibration scaffold, ported from `ParametricAeroModel`.
nonisolated struct ParametricAeroModel: Sendable {
    var cd0: Double = 0.225
    var cdSpinSlope: Double = 0.28
    var clSpinSlope: Double = 1.50
    var cdMin: Double = 0.15
    var cdMax: Double = 0.50
    var clMax: Double = 0.45

    /// Reynolds is accepted but unused by this starter parametrization.
    func coefficients(reynolds: Double, spinFactor: Double) -> (cd: Double, cl: Double) {
        let cd = min(max(cd0 + cdSpinSlope * spinFactor, cdMin), cdMax)
        let cl = min(max(clSpinSlope * spinFactor, 0.0), clMax)
        return (cd, cl)
    }
}

/// V1 candidate model: baseline drag * 0.97 with the KK raw lift relation, ported from `V1AeroModel`.
nonisolated struct V1AeroModel: Sendable {
    var baselineModel = ParametricAeroModel()
    var cdMultiplier: Double = 0.97

    func coefficients(reynolds: Double, spinFactor: Double) -> (cd: Double, cl: Double) {
        let (baselineCd, _) = baselineModel.coefficients(reynolds: reynolds, spinFactor: spinFactor)
        let clRaw = -3.25 * spinFactor * spinFactor + 1.99 * spinFactor
        let cl = max(0.0, clRaw)
        return (baselineCd * cdMultiplier, cl)
    }
}

/// Frozen Physics V1.1 configuration, ported from `physics_v11.py`. Do not retune.
nonisolated enum PhysicsV11Constants {
    static let version = "Physics V1.1"
    static let s1Upper = 0.08164632386599759
    static let s2Upper = 0.10409826875477744
    static let clLowSpinMultiplier = 1.06
}

/// V1.1 aerodynamic wrapper over V1 with smooth low-spin Cl taper, ported from `PhysicsV11AeroModel`.
nonisolated struct PhysicsV11AeroModel: Sendable {
    var baseV1Model = V1AeroModel()

    private func clMultiplier(spinFactor: Double) -> Double {
        if spinFactor <= PhysicsV11Constants.s1Upper {
            return PhysicsV11Constants.clLowSpinMultiplier
        }
        if spinFactor >= PhysicsV11Constants.s2Upper {
            return 1.0
        }
        let u = min(max(
            (spinFactor - PhysicsV11Constants.s1Upper) / (PhysicsV11Constants.s2Upper - PhysicsV11Constants.s1Upper),
            0.0
        ), 1.0)
        let smoothstep = 3.0 * u * u - 2.0 * u * u * u
        let weight = 1.0 - smoothstep
        return 1.0 + (PhysicsV11Constants.clLowSpinMultiplier - 1.0) * weight
    }

    func coefficients(reynolds: Double, spinFactor: Double) -> (cd: Double, cl: Double) {
        let (cdV1, clV1) = baseV1Model.coefficients(reynolds: reynolds, spinFactor: spinFactor)
        return (cdV1, clV1 * clMultiplier(spinFactor: spinFactor))
    }
}
