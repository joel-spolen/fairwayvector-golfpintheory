import Foundation

/// Physical constants and atmosphere helpers ported from `golf_flight_sim.py`.
nonisolated enum GolfConstants {
    static let gravityMps2 = 9.80665
    static let ballMassKg = 0.04593
    static let ballRadiusM = 0.021335
    static let ballDiameterM = 2.0 * ballRadiusM
    static let ballAreaM2 = Double.pi * ballRadiusM * ballRadiusM

    static let rDryAir = 287.05
    static let rWaterVapor = 461.495
}

nonisolated enum AtmosphereError: Error, LocalizedError {
    case invalidAltitude
    case invalidPressure

    var errorDescription: String? {
        switch self {
        case .invalidAltitude:
            return "Site elevation is outside the supported standard-atmosphere range."
        case .invalidPressure:
            return "Pressure must be greater than zero."
        }
    }
}

nonisolated enum Atmosphere {
    /// Smooth engineering approximation for saturation vapor pressure over water.
    static func saturationVaporPressurePa(temperatureC: Double) -> Double {
        611.2 * exp(17.67 * temperatureC / (temperatureC + 243.5))
    }

    /// Estimate station pressure (hPa) from site altitude (m ASL), ported from
    /// `standard_pressure_hpa_from_altitude_m`. Throws for altitudes outside the
    /// supported standard-atmosphere range.
    static func standardPressureHpa(fromAltitudeM altitudeM: Double) throws -> Double {
        let baseTerm = 1.0 - (altitudeM / 44330.0)
        guard baseTerm > 0.0 else {
            throw AtmosphereError.invalidAltitude
        }
        return 1013.25 * pow(baseTerm, 5.255)
    }

    static func altitudeM(fromStandardPressureHpa pressureHpa: Double) throws -> Double {
        guard pressureHpa > 0.0 else {
            throw AtmosphereError.invalidPressure
        }
        let altitudeM = 44330.0 * (1.0 - pow(pressureHpa / 1013.25, 1.0 / 5.255))
        guard altitudeM < 44330.0 else {
            throw AtmosphereError.invalidPressure
        }
        return altitudeM
    }

    /// Density of moist air from temperature, station pressure, and RH.
    static func moistAirDensityKgM3(
        temperatureC: Double,
        pressureHpa: Double,
        relativeHumidityPct: Double
    ) -> Double {
        let rh = min(max(relativeHumidityPct, 0.0), 100.0)
        let tempK = temperatureC + 273.15

        let pTotal = pressureHpa * 100.0
        let pSat = saturationVaporPressurePa(temperatureC: temperatureC)
        var pVapor = (rh / 100.0) * pSat
        // Prevent impossible vapor partial pressure from breaking the mixture model.
        pVapor = min(pVapor, 0.99 * pTotal)
        let pDry = pTotal - pVapor

        return pDry / (GolfConstants.rDryAir * tempK) + pVapor / (GolfConstants.rWaterVapor * tempK)
    }

    /// Dynamic viscosity of air via Sutherland's law.
    static func dynamicViscosityAirPaS(temperatureC: Double) -> Double {
        let tempK = temperatureC + 273.15
        let mu0 = 1.716e-5
        let t0 = 273.15
        let sutherlandK = 111.0
        return mu0 * pow(tempK / t0, 1.5) * (t0 + sutherlandK) / (tempK + sutherlandK)
    }
}
