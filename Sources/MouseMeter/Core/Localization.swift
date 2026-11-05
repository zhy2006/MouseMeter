import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    /// Resolve regional variants using the system's ordered language preferences.
    func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        return Bundle.preferredLocalizations(
            from: ["en", "zh-Hans", "ja"], forPreferences: preferredLanguages
        ).first ?? "en"
    }
}

enum L10n {
    // SwiftPM's generated accessor searches the executable directory. Packaged
    // macOS apps keep resources in Contents/Resources instead.
    static let resourceBundle: Bundle = {
        if let url = Bundle.main.url(forResource: "MouseMeter_MouseMeter", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: SettingsKey.language) ?? "system") ?? .system
    }

    static var locale: Locale {
        Locale(identifier: language.resolvedIdentifier())
    }

    static func text(_ key: String) -> String {
        text(key, language: language)
    }

    static func text(_ key: String, language: AppLanguage) -> String {
        let identifier = language.resolvedIdentifier()
        let folder = resourceBundle.localizations.first {
            $0.caseInsensitiveCompare(identifier) == .orderedSame
        } ?? identifier
        guard let path = resourceBundle.path(forResource: folder, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}
