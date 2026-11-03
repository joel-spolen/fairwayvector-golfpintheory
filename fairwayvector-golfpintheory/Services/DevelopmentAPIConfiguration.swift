import Foundation

/// Build-time only: no persisted/runtime switch can accidentally enable paid providers.
nonisolated struct DevelopmentAPIConfiguration: Sendable {
    enum Mode: String, Sendable {
        case mock, live
        init(setting: String?) {
            // Missing, blank, misspelled and unexpanded settings all fail safely to mock.
            self = setting?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "live" ? .live : .mock
        }
    }

    let golfAPI: Mode
    let gpxz: Mode
    static var current: Self {
        #if DEBUG
        // Without sign-in there is no token for the live data service.
        if Bundle.main.object(forInfoDictionaryKey: "GOLFPINTHEORY_SKIP_SIGN_IN") as? String == "YES" {
            return Self(golfAPI: .mock, gpxz: .mock)
        }
        #endif
        return Self(golfAPI: Mode(setting: Bundle.main.object(forInfoDictionaryKey: "GOLF_API_MODE") as? String),
             gpxz: Mode(setting: Bundle.main.object(forInfoDictionaryKey: "GPXZ_API_MODE") as? String))
    }
    static let syntheticSource = "Synthetic development terrain"
    static func isDemoCourse(_ id: String) -> Bool { id.contains("mock-hills-v1") }
}