import AppKit
import IOKit.hid
import SwiftUI

@main
struct MouseMeterApp: App {
    @AppStorage(SettingsKey.language) private var language = AppLanguage.system.rawValue
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(appDelegate.monitor)
                .environmentObject(appDelegate.navigation)
                .environmentObject(appDelegate.updater)
                .environment(\.locale, L10n.locale)
                .id(language)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.monitor)
                .environment(\.locale, L10n.locale)
                .id(language)
        }
        .menuBarExtraStyle(.window)

        Window("MouseMeter", id: AppNavigation.mainWindowID) {
            MainWindowView()
                .environmentObject(appDelegate.monitor)
                .environmentObject(appDelegate.navigation)
                .environmentObject(appDelegate.updater)
                .environment(\.locale, L10n.locale)
                .id(language)
        }
        .defaultSize(width: 880, height: 600)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = DeviceMonitor(providers: ProviderRegistry.makeDefault())
    let navigation = AppNavigation()
    let updater = UpdateManager()

    override init() {
        SettingsKey.registerDefaults()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--dump") {
            dumpDevicesAndExit()
            return
        }
        monitor.start()
        updater.start()
        Notifier.requestAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// `MouseMeter --dump`：读取一次所有 provider 并打印到终端，开发新协议时用来调试
    private func dumpDevicesAndExit() {
        monitor.providers.forEach { $0.start() }
        Task {
            await monitor.refresh()
            if monitor.needsInputMonitoringPermission { print(L10n.text("需要输入监控权限")) }
            if monitor.devices.isEmpty { print(L10n.text("未发现设备")) }
            for device in monitor.devices {
                print(device.name, "|", device.vendor, device.connection.title, device.protocolName)
                print(L10n.text("dump_battery"), device.battery.map { "\($0.percentText) \($0.state.title)" } ?? "-")
                print("  DPI :", device.dpi.map { L10n.format("dump_dpi", $0.displayText, $0.defaultValue ?? 0, $0.range.map { "\($0)" } ?? "-") } ?? "-")
            }
            exit(0)
        }
    }
}

enum PermissionHelper {
    static func requestInputMonitoring() {
        // 首次调用会弹出系统授权框；已拒绝过则直接跳到对应设置页
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
