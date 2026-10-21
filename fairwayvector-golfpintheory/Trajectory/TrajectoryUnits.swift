import Foundation
import SwiftUI

enum UnitSystem: String, CaseIterable, Identifiable {
    case imperial
    case metric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .imperial: return "Imperial"
        case .metric: return "Metric"
        }
    }
}

/// The specific shot-input/result fields a user can independently set imperial or metric for.
enum UnitField: String, CaseIterable, Identifiable {
    case ballSpeed
    case windSpeed
    case landingSpeed
    case distance
    case temperature
    case pressure

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ballSpeed: return "Ball Speed"
        case .windSpeed: return "Wind Speed"
        case .landingSpeed: return "Landing Speed"
        case .distance: return "Distance & Height"
        case .temperature: return "Temperature"
        case .pressure: return "Pressure"
        }
    }
}

/// Conversion helpers between the app's display units and the simulator's internal metric units.
enum Units {
    static func mpsFromMph(_ mph: Double) -> Double { mph * 0.44704 }
    static func mphFromMps(_ mps: Double) -> Double { mps / 0.44704 }

    static func metersFromYards(_ yards: Double) -> Double { yards * 0.9144 }
    static func yardsFromMeters(_ meters: Double) -> Double { meters / 0.9144 }

    static func metersFromFeet(_ feet: Double) -> Double { feet * 0.3048 }
    static func feetFromMeters(_ meters: Double) -> Double { meters / 0.3048 }

    static func celsiusFromFahrenheit(_ f: Double) -> Double { (f - 32.0) * 5.0 / 9.0 }
    static func fahrenheitFromCelsius(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }

    static func hpaFromInHg(_ inHg: Double) -> Double { inHg * 33.8639 }
    static func inHgFromHpa(_ hpa: Double) -> Double { hpa / 33.8639 }

    static func formattedDistance(meters: Double, system: UnitSystem) -> String {
        switch system {
        case .imperial:
            return String(format: "%.1f yd", yardsFromMeters(meters))
        case .metric:
            return String(format: "%.1f m", meters)
        }
    }

    static func formattedHeight(meters: Double, system: UnitSystem) -> String {
        switch system {
        case .imperial:
            return String(format: "%.0f ft", feetFromMeters(meters))
        case .metric:
            return String(format: "%.1f m", meters)
        }
    }

    static func formattedSpeed(mps: Double, system: UnitSystem) -> String {
        switch system {
        case .imperial:
            return String(format: "%.1f mph", mphFromMps(mps))
        case .metric:
            return String(format: "%.1f m/s", mps)
        }
    }

    static func formattedPressure(hpa: Double, system: UnitSystem) -> String {
        switch system {
        case .imperial:
            return String(format: "%.2f inHg", inHgFromHpa(hpa))
        case .metric:
            return String(format: "%.1f hPa", hpa)
        }
    }
}

