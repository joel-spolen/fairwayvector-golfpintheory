import Combine
import Foundation
import SwiftUI

/// A global default unit system plus optional per-field overrides. Views resolve
/// the effective unit system for a field via `unitSystem(for:)`.
final class UnitPreferences: ObservableObject {
    @AppStorage("unitPreferences.globalDefault") private var globalDefaultRaw: String = UnitSystem.imperial.rawValue
    @AppStorage("unitPreferences.overrides") private var overridesRaw: String = "{}"

    var globalDefault: UnitSystem {
        get { UnitSystem(rawValue: globalDefaultRaw) ?? .imperial }
        set {
            globalDefaultRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    private var overrides: [String: String] {
        get {
            let data = Data(overridesRaw.utf8)
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8)
            overridesRaw = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    func unitSystem(for field: UnitField) -> UnitSystem {
        overrides[field.rawValue].flatMap(UnitSystem.init(rawValue:)) ?? globalDefault
    }

    /// `nil` means "use the global default" for this field.
    func override(for field: UnitField) -> UnitSystem? {
        overrides[field.rawValue].flatMap(UnitSystem.init(rawValue:))
    }

    func setOverride(_ system: UnitSystem?, for field: UnitField) {
        var current = overrides
        if let system {
            current[field.rawValue] = system.rawValue
        } else {
            current.removeValue(forKey: field.rawValue)
        }
        overrides = current
        objectWillChange.send()
    }
}
