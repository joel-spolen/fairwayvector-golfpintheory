import Foundation

/// Build-time only: no persisted/runtime switch can accidentally enable paid providers.
nonisolated struct DevelopmentAPIConfiguration: Sendable {
    enum Mode: String, Sendable {
        case mock, live
        init(setting: String?) {
            // Missing, blank, misspelled and unexpanded settings all fail safely to mock.
            self = setting?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "live" ? .live : .mock
        }
        var status: String { self == .mock ? "Mock · 0 paid requests" : "LIVE · paid requests enabled" }
    }

    let golfAPI: Mode
    let gpxz: Mode
    static var current: Self {
        Self(golfAPI: Mode(setting: Bundle.main.object(forInfoDictionaryKey: "GOLF_API_MODE") as? String),
             gpxz: Mode(setting: Bundle.main.object(forInfoDictionaryKey: "GPXZ_API_MODE") as? String))
    }
    static let syntheticSource = "Synthetic development terrain"
    static let terrainNamespace = "development-gpxz-v1:"
    static func isDemoCourse(_ id: String) -> Bool { id.contains("mock-hills-v1") }
}