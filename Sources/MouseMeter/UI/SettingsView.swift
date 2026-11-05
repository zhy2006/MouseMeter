import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: DeviceMonitor
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
            Section("菜单栏") {
                Picker("显示设备", selection: $menuBarDeviceID) {
                    Text("自动").tag("")
                    ForEach(monitor.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                Toggle("显示电量百分比", isOn: $showsPercent)
                Toggle("显示当前 DPI", isOn: $showsDPI)
            }

            Section("刷新") {
                Picker("刷新间隔", selection: $refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }
                }
                .onChange(of: refreshInterval) { monitor.restartPolling() }
            }

            Section("通知") {
                Toggle("低电量提醒", isOn: $lowBatteryAlert)
                Stepper(value: $lowBatteryThreshold, in: 5...50, step: 5) {
                    LabeledContent("提醒阈值", value: "\(lowBatteryThreshold)%")
                }
                .disabled(!lowBatteryAlert)
            }

            Section("启动") {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(monitor.providers, id: \.id) { provider in
                    LabeledContent(provider.displayName) {
                        Text("优先级 \(provider.priority)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("已启用的协议")
            } footer: {
                Text("同一只鼠标被多个协议识别时，使用优先级更高的数据源。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
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
            launchAtLoginError = "设置失败：\(error.localizedDescription)（需要以 .app 形式运行）"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
