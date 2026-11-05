import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: DeviceMonitor
    @EnvironmentObject private var updater: UpdateManager
    @AppStorage(SettingsKey.automaticallyCheckUpdates) private var automaticallyCheckUpdates = true
    @AppStorage(SettingsKey.language) private var language = AppLanguage.system.rawValue
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = RefreshInterval.oneMinute.rawValue
    @AppStorage(SettingsKey.menuBarShowsPercent) private var showsPercent = true
    @AppStorage(SettingsKey.menuBarShowsDPI) private var showsDPI = false
    @AppStorage(SettingsKey.menuBarDeviceID) private var menuBarDeviceID = ""
    @AppStorage(SettingsKey.lowBatteryAlertEnabled) private var lowBatteryAlert = true
    @AppStorage(SettingsKey.lowBatteryThreshold) private var lowBatteryThreshold = 20
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section(L10n.text("update_section")) {
                LabeledContent(L10n.text("update_current_version"), value: updater.currentVersion)
                Toggle(L10n.text("update_auto_check"), isOn: $automaticallyCheckUpdates)
                    .onChange(of: automaticallyCheckUpdates) { _, enabled in
                        if enabled { Task { await updater.checkIfDue() } }
                    }
                HStack {
                    Button(L10n.text("update_check")) {
                        Task { await updater.checkForUpdates() }
                    }
                    .disabled(updater.isChecking || updater.isInstalling)
                    if updater.isChecking { ProgressView().controlSize(.small) }
                    Link(L10n.text("update_releases"), destination: UpdateManager.releasesURL)
                }
                if let update = updater.availableUpdate {
                    Text(L10n.format("update_available", update.version))
                    Button(L10n.text("update_install")) {
                        Task { await updater.installUpdate() }
                    }
                    .disabled(updater.isInstalling || updater.isChecking)
                } else if updater.checked && updater.errorMessage == nil {
                    Text(L10n.text("update_current")).foregroundStyle(.secondary)
                }
                if updater.isInstalling {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(L10n.text("update_installing"))
                    }
                }
                if let error = updater.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }

            Section(L10n.text("语言")) {
                Picker(L10n.text("当前语言"), selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
            }

            Section(L10n.text("菜单栏")) {
                Picker(L10n.text("显示设备"), selection: $menuBarDeviceID) {
                    Text(L10n.text("自动")).tag("")
                    ForEach(monitor.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                Toggle(L10n.text("显示电量百分比"), isOn: $showsPercent)
                Toggle(L10n.text("显示当前 DPI"), isOn: $showsDPI)
            }

            Section(L10n.text("刷新")) {
                Picker(L10n.text("刷新间隔"), selection: $refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .onChange(of: refreshInterval) { monitor.restartPolling() }
            }

            Section(L10n.text("通知")) {
                Toggle(L10n.text("低电量提醒"), isOn: $lowBatteryAlert)
                Stepper(value: $lowBatteryThreshold, in: 5...50, step: 5) {
                    LabeledContent(L10n.text("提醒阈值"), value: "\(lowBatteryThreshold)%")
                }
                .disabled(!lowBatteryAlert)
            }

            Section(L10n.text("启动")) {
                Toggle(L10n.text("登录时启动"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(monitor.providers, id: \.id) { provider in
                    LabeledContent(provider.displayName) {
                        Text(L10n.format("priority", provider.priority))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L10n.text("已启用的协议"))
            } footer: {
                Text(L10n.text("同一只鼠标被多个协议识别时，使用优先级更高的数据源。"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L10n.text("设置"))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = L10n.format("login_error", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
