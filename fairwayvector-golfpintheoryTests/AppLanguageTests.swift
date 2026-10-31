import Foundation
import Testing
@testable import fairwayvector_golfpintheory

struct AppLanguageTests {
    @Test func supportsAllSeventeenRequestedLanguages() {
        #expect(AppLanguage.allCases.count == 17)
        #expect(Set(AppLanguage.allCases.map(\.rawValue)) == Set([
            "en", "sv", "da", "nb", "fi", "is", "de", "fr", "es", "it", "nl",
            "pt-PT", "pl", "cs", "ja", "ko", "zh-Hans"
        ]))
        #expect(AppLanguage.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test func explicitChoiceWinsAndSystemChoiceUsesPreferenceOrder() {
        #expect(AppLanguage.resolve(preference: "ja", systemPreferredLanguages: ["sv-SE"]) == .japanese)
        #expect(AppLanguage.resolve(preference: "invalid", systemPreferredLanguages: ["de-DE"]) == .german)
        #expect(AppLanguage.resolve(preference: AppLanguage.followSystemValue,
            systemPreferredLanguages: ["es-MX", "sv-SE"]) == .spanish)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["xx", "fi-FI"]) == .finnish)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: []) == .english)
    }

    @Test func systemLanguageVariantsMapToRequestedScriptsAndVariants() {
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["no-NO"]) == .norwegianBokmal)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["nb-NO"]) == .norwegianBokmal)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["pt-BR"]) == .portuguesePortugal)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["zh-CN"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["zh-SG"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["zh-Hans-TW"]) == .simplifiedChinese)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["zh-Hant-TW"]) == .english)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["zh-Hant-TW", "fr-FR"]) == .french)
        #expect(AppLanguage.resolve(preference: nil, systemPreferredLanguages: ["nn-NO"]) == .english)
    }

    @Test func appLanguageLocalePreservesDeviceRegionAndSetsChineseScript() {
        let german = AppLanguage.locale(preference: "de", deviceLocale: Locale(identifier: "sv-SE"),
            systemPreferredLanguages: ["en-US"])
        #expect(german.language.languageCode?.identifier == "de")
        #expect(german.region?.identifier == "SE")

        let chinese = AppLanguage.locale(preference: "zh-Hans", deviceLocale: Locale(identifier: "en-CA"),
            systemPreferredLanguages: ["en-US"])
        #expect(chinese.language.languageCode?.identifier == "zh")
        #expect(chinese.language.script?.identifier == "Hans")
        #expect(chinese.region?.identifier == "CA")
    }

    @Test func catalogLookupUsesManualLanguageAndFormatsDynamicValues() {
        #expect(AppLanguage.localized("App language", preference: "sv") == "Appspråk")
        #expect(AppLanguage.localized("No golf clubs matched \"%@\".", preference: "ja",
            arguments: ["東京"] ) == "「東京」に一致するゴルフクラブはありません。")
        #expect(AppLanguage.localized("App language", preference: "en") == "App language")
    }
}
