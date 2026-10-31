import Foundation

/// App interface languages. Persisted raw values are stable preference identifiers,
/// not localized display names or device-region settings.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case swedish = "sv"
    case danish = "da"
    case norwegianBokmal = "nb"
    case finnish = "fi"
    case icelandic = "is"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case dutch = "nl"
    case portuguesePortugal = "pt-PT"
    case polish = "pl"
    case czech = "cs"
    case japanese = "ja"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"

    static let preferenceKey = "app.language.preference.v1"
    static let followSystemValue = "system"
    private static let appBundle = Bundle.main

    var id: String { rawValue }

    /// Native language names are intentionally self-labeled regardless of the app language.
    var displayName: String {
        switch self {
        case .english: "English"
        case .swedish: "Svenska"
        case .danish: "Dansk"
        case .norwegianBokmal: "Norsk bokmål"
        case .finnish: "Suomi"
        case .icelandic: "Íslenska"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .dutch: "Nederlands"
        case .portuguesePortugal: "Português (Portugal)"
        case .polish: "Polski"
        case .czech: "Čeština"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .simplifiedChinese: "简体中文"
        }
    }

    var languageCode: String {
        switch self {
        case .portuguesePortugal: "pt"
        case .simplifiedChinese: "zh"
        default: rawValue
        }
    }

    var scriptCode: String? {
        self == .simplifiedChinese ? "Hans" : nil
    }

    /// An explicit choice wins. Otherwise honor the first supported language in iOS's
    /// ordered language preference list; English is the final fallback.
    static func resolve(preference: String?, systemPreferredLanguages: [String]) -> AppLanguage {
        if let preference, preference != followSystemValue,
           let selected = AppLanguage(rawValue: preference) {
            return selected
        }
        for identifier in systemPreferredLanguages {
            if let language = supportedLanguage(for: Locale(identifier: identifier)) {
                return language
            }
        }
        return .english
    }

    /// Retain the phone's regional conventions while changing only the interface language.
    static func locale(preference: String?, deviceLocale: Locale = .current,
                       systemPreferredLanguages: [String] = Locale.preferredLanguages) -> Locale {
        let language = resolve(preference: preference, systemPreferredLanguages: systemPreferredLanguages)
        let region = language == .portuguesePortugal ? "PT" : deviceLocale.region?.identifier
        let identifier = [language.languageCode, language.scriptCode, region]
            .compactMap { $0 }
            .joined(separator: "-")
        return Locale(identifier: identifier)
    }

    /// Resolve standalone model/service messages using the same device preference as SwiftUI.
    /// String catalogs remain the source of truth; dynamic values are formatted with the
    /// selected language while retaining the device's region-specific number conventions.
    static func localized(_ key: String, preference: String? = UserDefaults.standard.string(forKey: preferenceKey),
                          arguments: [CVarArg] = [], deviceLocale: Locale = .current,
                          systemPreferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let language = resolve(preference: preference, systemPreferredLanguages: systemPreferredLanguages)
        // English is the source language and has no en.lproj directory; using the source key
        // avoids falling back to the device language.
        let translated = language == .english ? key : (appBundle.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? appBundle).localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return translated }
        return String(format: translated, locale: locale(preference: preference, deviceLocale: deviceLocale,
            systemPreferredLanguages: systemPreferredLanguages), arguments: arguments)
    }

    private static func supportedLanguage(for locale: Locale) -> AppLanguage? {
        let code = locale.language.languageCode?.identifier.lowercased()
        let region = locale.region?.identifier.uppercased()
        let script = locale.language.script?.identifier

        switch code {
        case "en": return .english
        case "sv": return .swedish
        case "da": return .danish
        case "nb", "no": return .norwegianBokmal
        case "nn": return nil // Nynorsk is not Bokmål.
        case "fi": return .finnish
        case "is": return .icelandic
        case "de": return .german
        case "fr": return .french
        case "es": return .spanish
        case "it": return .italian
        case "nl": return .dutch
        case "pt": return .portuguesePortugal
        case "pl": return .polish
        case "cs": return .czech
        case "ja": return .japanese
        case "ko": return .korean
        case "zh":
            if script == "Hans" { return .simplifiedChinese }
            if script == "Hant" || ["TW", "HK", "MO"].contains(region) { return nil }
            if script == nil || ["CN", "SG", "MY"].contains(region) { return .simplifiedChinese }
            return nil
        default: return nil
        }
    }
}

/// Looks up an English source string in the selected app language's Localizable.strings.
nonisolated func L(_ key: String, _ arguments: String...) -> String {
    AppLanguage.localized(key, arguments: arguments)
}
