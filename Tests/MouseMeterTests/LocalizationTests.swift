import Foundation
import Testing
@testable import MouseMeter

struct LocalizationTests {
    @Test func resolvesSystemLanguageAndRegionalVariants() {
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["ja-JP", "en-US"]) == "ja")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-CN", "en-US"]) == "zh-Hans")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["en-GB"]) == "en")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR", "ja-JP"]) == "ja")
        #expect(AppLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR"]) == "en")
        #expect(AppLanguage.japanese.resolvedIdentifier(preferredLanguages: ["en-US"]) == "ja")
    }

    @Test func loadsTranslationsFromResources() {
        #expect(L10n.text("设置", language: .english) == "Settings")
        #expect(L10n.text("设置", language: .japanese) == "設定")
        #expect(L10n.text("设置", language: .simplifiedChinese) == "设置")
        #expect(L10n.text("unknown-key", language: .english) == "unknown-key")
    }

    @Test func translationTablesHaveMatchingKeysAndFormatSpecifiers() throws {
        let tables = try ["en", "ja", "zh-hans"].map { language -> [String: String] in
            let url = try #require(L10n.resourceBundle.url(
                forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj"
            ))
            let data = try Data(contentsOf: url)
            return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = tables[0]
        let formatPattern = try Regex("%[@d%]")
        for table in tables {
            #expect(Set(table.keys) == Set(english.keys))
            for (key, value) in table {
                let reference = try #require(english[key])
                #expect(!value.isEmpty)
                #expect(value.matches(of: formatPattern).map { String($0.output[0].substring!) }
                        == reference.matches(of: formatPattern).map { String($0.output[0].substring!) })
            }
        }
    }

    @Test func formatsNotificationsInAllLanguages() {
        for language in [AppLanguage.english, .japanese, .simplifiedChinese] {
            let title = String(format: L10n.text("low_battery_title", language: language), "Test Mouse")
            let body = String(format: L10n.text("low_battery_body", language: language), 15)
            #expect(title.contains("Test Mouse"))
            #expect(body.contains("15%"))
            #expect(!body.contains("%d"))
        }
    }
}
