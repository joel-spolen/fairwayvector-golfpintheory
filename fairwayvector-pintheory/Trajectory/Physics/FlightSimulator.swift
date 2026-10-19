import Foundation

/// Launch state, environment, and target geometry for one shot. Ported from `ShotInputs`.
nonisolated struct ShotInputs: Sendable {
    var ballSpeedMps: Double
    var launchAngleDeg: Double
    var launchDirectionDeg: Double
    var spinRateRpm: Double
    var spinAxisDeg: Double

    var temperatureC: Double = 20.0
    var pressureHpa: Double = 1013.25
    var relativeHumidityPct: Double = 50.0

    var windXMps: Double = 0.0
    var windYMps: Double = 0.0
    var windZMps: Double = 0.0

    var targetElevationDeltaM: Double = 0.0
}

/// Full sampled flight path in ground-fixed axes (x = downrange, y = right, z = up).
nonisolated struct GolfTrajectory: Sendable {
    var tS: [Double] = []
    var xM: [Double] = []
    var yM: [Double] = []
    var zM: [Double] = []
    var vxMps: [Double] = []
    var vyMps: [Double] = []
    var vzMps: [Double] = []
    var spinRpm: [Double] = []
}

/// Scalar and trajectory outputs for one simulated shot. Ported from `FlightResult`.
nonisolated struct FlightResult: Sendable {
    var landed: Bool

    var actualTerrainCarryM: Double?
    var levelGroundCarryM: Double?
    var downrangeM: Double?
    var lateralCarryM: Double?

    var apexHeightM: Double
    var apexAboveTargetM: Double
    var flightTimeS: Double?
    var landingAngleDeg: Double?
    var landingSpeedMps: Double?

    var airDensityKgM3: Double
    var trajectory: GolfTrajectory
}

/// Simple 3-vector for the flight-dynamics state, avoiding a SIMD dependency.
nonisolated private struct Vec3 {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vec3(x: 0, y: 0, z: 0)

    static func + (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z) }
    static func - (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z) }
    static func * (lhs: Vec3, rhs: Double) -> Vec3 { Vec3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs) }

    var norm: Double { (x * x + y * y + z * z).squareRoot() }

    func cross(_ other: Vec3) -> Vec3 {
        Vec3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }
}

/// State vector integrated by RK4: [x, y, z, vx, vy, vz, omega_rad_s].
nonisolated private struct FlightState {
    var position: Vec3
    var velocity: Vec3
    var omega: Double

    static func + (lhs: FlightState, rhs: FlightState) -> FlightState {
        FlightState(position: lhs.position + rhs.position, velocity: lhs.velocity + rhs.velocity, omega: lhs.omega + rhs.omega)
    }
    static func * (lhs: FlightState, rhs: Double) -> FlightState {
        FlightState(position: lhs.position * rhs, velocity: lhs.velocity * rhs, omega: lhs.omega * rhs)
    }
}

nonisolated enum FlightSimulator {
    static func simulateShot(
        _ shot: ShotInputs,
        aero: PhysicsV11AeroModel = PhysicsV11AeroModel(),
        dtS: Double = 0.01,
        maxTimeS: Double = 20.0,
        spinDecayPerS: Double = 0.0
    ) -> FlightResult {
        precondition(shot.ballSpeedMps > 0, "ballSpeedMps must be positive")
        precondition(shot.spinRateRpm >= 0, "spinRateRpm must be non-negative")
        precondition(dtS > 0, "dtS must be positive")
        precondition(maxTimeS > 0, "maxTimeS must be positive")

        let (hitTime, hitState, rows, rho) = integrate(
            shot: shot,
            targetHeightM: shot.targetElevationDeltaM,
            aero: aero,
            dtS: dtS,
            maxTimeS: maxTimeS,
            spinDecayPerS: spinDecayPerS,
            keepTrajectory: true
        )

        let levelHitState: FlightState?
        if abs(shot.targetElevationDeltaM) < 1e-12 {
            levelHitState = hitState
        } else {
            let (_, state, _, _) = integrate(
                shot: shot,
                targetHeightM: 0.0,
                aero: aero,
                dtS: dtS,
                maxTimeS: maxTimeS,
                spinDecayPerS: spinDecayPerS,
                keepTrajectory: false
            )
            levelHitState = state
        }

        var apexHeight = 0.0
        var trajectory = GolfTrajectory()
        if !rows.isEmpty {
            apexHeight = rows.map { $0.1.position.z }.max() ?? 0.0
            for (t, state) in rows {
                trajectory.tS.append(t)
                trajectory.xM.append(state.position.x)
                trajectory.yM.append(state.position.y)
                trajectory.zM.append(state.position.z)
                trajectory.vxMps.append(state.velocity.x)
                trajectory.vyMps.append(state.velocity.y)
                trajectory.vzMps.append(state.velocity.z)
                trajectory.spinRpm.append(state.omega * 60.0 / (2.0 * Double.pi))
            }
        }

        var levelCarry: Double?
        if let levelHitState {
            levelCarry = hypot(levelHitState.position.x, levelHitState.position.y)
        }

        guard let hitState, let hitTime else {
            return FlightResult(
                landed: false,
                actualTerrainCarryM: nil,
                levelGroundCarryM: levelCarry,
                downrangeM: nil,
                lateralCarryM: nil,
                apexHeightM: apexHeight,
                apexAboveTargetM: apexHeight - shot.targetElevationDeltaM,
                flightTimeS: nil,
                landingAngleDeg: nil,
                landingSpeedMps: nil,
                airDensityKgM3: rho,
                trajectory: trajectory
            )
        }

        let landingV = hitState.velocity
        let horizontalSpeed = hypot(landingV.x, landingV.y)
        let landingAngle = atan2(-landingV.z, horizontalSpeed) * 180.0 / Double.pi
        let landingSpeed = landingV.norm

        return FlightResult(
            landed: true,
            actualTerrainCarryM: hypot(hitState.position.x, hitState.position.y),
            levelGroundCarryM: levelCarry,
            downrangeM: hitState.position.x,
            lateralCarryM: hitState.position.y,
            apexHeightM: apexHeight,
            apexAboveTargetM: apexHeight - shot.targetElevationDeltaM,
            flightTimeS: hitTime,
            landingAngleDeg: landingAngle,
            landingSpeedMps: landingSpeed,
            airDensityKgM3: rho,
            trajectory: trajectory
        )
    }

    private static func initialVelocity(speedMps: Double, launchAngleDeg: Double, launchDirectionDeg: Double) -> Vec3 {
        let elev = launchAngleDeg * Double.pi / 180.0
        let az = launchDirectionDeg * Double.pi / 180.0
        return Vec3(
            x: speedMps * cos(elev) * cos(az),
            y: speedMps * cos(elev) * sin(az),
            z: speedMps * sin(elev)
        )
    }

    /// TrackMan-style sign convention: spinAxis 0 = pure backspin, positive curves right.
    private static func spinAxisUnit(launchDirectionDeg: Double, spinAxisDeg: Double) -> Vec3 {
        let az = launchDirectionDeg * Double.pi / 180.0
        let phi = spinAxisDeg * Double.pi / 180.0

        let right = Vec3(x: -sin(az), y: cos(az), z: 0.0)
        let up = Vec3(x: 0.0, y: 0.0, z: 1.0)

        let axis = right * (-cos(phi)) + up * sin(phi)
        return axis * (1.0 / axis.norm)
    }

    private static func rk4Step(_ rhs: (FlightState) -> FlightState, state: FlightState, dt: Double) -> FlightState {
        let k1 = rhs(state)
        let k2 = rhs(state + k1 * (0.5 * dt))
        let k3 = rhs(state + k2 * (0.5 * dt))
        let k4 = rhs(state + k3 * dt)
        return state + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (dt / 6.0)
    }

    private static func integrate(
        shot: ShotInputs,
        targetHeightM: Double,
        aero: PhysicsV11AeroModel,
        dtS: Double,
        maxTimeS: Double,
        spinDecayPerS: Double,
        keepTrajectory: Bool
    ) -> (hitTime: Double?, hitState: FlightState?, rows: [(Double, FlightState)], rho: Double) {
        let rho = Atmosphere.moistAirDensityKgM3(
            temperatureC: shot.temperatureC,
            pressureHpa: shot.pressureHpa,
            relativeHumidityPct: shot.relativeHumidityPct
        )
        let mu = Atmosphere.dynamicViscosityAirPaS(temperatureC: shot.temperatureC)
        let wind = Vec3(x: shot.windXMps, y: shot.windYMps, z: shot.windZMps)

        let v0 = initialVelocity(
            speedMps: shot.ballSpeedMps,
            launchAngleDeg: shot.launchAngleDeg,
            launchDirectionDeg: shot.launchDirectionDeg
        )
        let spinAxis = spinAxisUnit(launchDirectionDeg: shot.launchDirectionDeg, spinAxisDeg: shot.spinAxisDeg)
        let omega0 = shot.spinRateRpm * 2.0 * Double.pi / 60.0

        var state = FlightState(position: .zero, velocity: v0, omega: omega0)

        func rhs(_ s: FlightState) -> FlightState {
            let vRel = s.velocity - wind
            let relSpeed = vRel.norm

            var accel = Vec3(x: 0.0, y: 0.0, z: -GolfConstants.gravityMps2)

            if relSpeed > 1e-10 {
                let reynolds = rho * relSpeed * GolfConstants.ballDiameterM / mu
                let spinFactor = GolfConstants.ballRadiusM * abs(s.omega) / relSpeed
                let (cd, cl) = aero.coefficients(reynolds: reynolds, spinFactor: spinFactor)

                let vRelHat = vRel * (1.0 / relSpeed)
                let dynamicPressure = 0.5 * rho * relSpeed * relSpeed

                let dragForce = vRelHat * (-dynamicPressure * GolfConstants.ballAreaM2 * cd)

                let liftDir = spinAxis.cross(vRelHat)
                let liftNorm = liftDir.norm

                var liftForce = Vec3.zero
                if liftNorm > 1e-12 && cl > 0.0 {
                    liftForce = (liftDir * (1.0 / liftNorm)) * (dynamicPressure * GolfConstants.ballAreaM2 * cl)
                }

                accel = accel + (dragForce + liftForce) * (1.0 / GolfConstants.ballMassKg)
            }

            let domega = -spinDecayPerS * s.omega
            return FlightState(position: s.velocity, velocity: accel, omega: domega)
        }

        var t = 0.0
        var descendingSeen = state.velocity.z < 0.0

        var rows: [(Double, FlightState)] = []
        if keepTrajectory {
            rows.append((t, state))
        }

        var hitState: FlightState?
        var hitTime: Double?

        while t < maxTimeS {
            let nextState = rk4Step(rhs, state: state, dt: dtS)
            let nextT = t + dtS

            if nextState.velocity.z < 0.0 {
                descendingSeen = true
            }

            let crossedDownward = descendingSeen
                && state.position.z >= targetHeightM
                && nextState.position.z < targetHeightM

            if crossedDownward {
                let denom = state.position.z - nextState.position.z
                var frac = denom != 0 ? (state.position.z - targetHeightM) / denom : 0.0
                frac = min(max(frac, 0.0), 1.0)

                var interpolated = state + (nextState + state * -1.0) * frac
                interpolated.position.z = targetHeightM
                hitState = interpolated
                hitTime = t + frac * dtS

                if keepTrajectory {
                    rows.append((hitTime!, interpolated))
                }
                break
            }

            state = nextState
            t = nextT

            if keepTrajectory {
                rows.append((t, state))
            }
        }

        return (hitTime, hitState, rows, rho)
    }
}
