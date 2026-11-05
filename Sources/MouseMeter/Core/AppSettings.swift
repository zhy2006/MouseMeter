import Foundation

/// UserDefaults 键与默认值。视图里用 `@AppStorage(SettingsKey.xxx)` 读写。
enum SettingsKey {
    static let automaticallyCheckUpdates = "automaticallyCheckUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"
    static let language = "appLanguage"
    static let refreshInterval = "refreshInterval"
    static let menuBarShowsPercent = "menuBarShowsPercent"
    static let menuBarShowsDPI = "menuBarShowsDPI"
    static let menuBarDeviceID = "menuBarDeviceID"
    static let lowBatteryAlertEnabled = "lowBatteryAlertEnabled"
    static let lowBatteryThreshold = "lowBatteryThreshold"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            language: AppLanguage.system.rawValue,
            automaticallyCheckUpdates: true,
            refreshInterval: 60.0,
            menuBarShowsPercent: true,
            menuBarShowsDPI: false,
            menuBarDeviceID: "",
            lowBatteryAlertEnabled: true,
            lowBatteryThreshold: 20,
        ])
    }
}

enum RefreshInterval: Double, CaseIterable, Identifiable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300

    var id: Double { rawValue }

    var title: String {
        rawValue < 60 ? L10n.format("seconds", Int(rawValue)) : L10n.format("minutes", Int(rawValue / 60))
    }
}
