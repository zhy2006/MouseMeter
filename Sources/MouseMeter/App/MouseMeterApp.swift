import AppKit
import IOKit.hid
import SwiftUI

@main
struct MouseMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(appDelegate.monitor)
                .environmentObject(appDelegate.navigation)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.monitor)
        }
        .menuBarExtraStyle(.window)

        Window("MouseMeter", id: AppNavigation.mainWindowID) {
            MainWindowView()
                .environmentObject(appDelegate.monitor)
                .environmentObject(appDelegate.navigation)
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
            if monitor.needsInputMonitoringPermission { print("需要输入监控权限") }
            if monitor.devices.isEmpty { print("未发现设备") }
            for device in monitor.devices {
                print(device.name, "|", device.vendor, device.connection.title, device.protocolName)
                print("  电量:", device.battery.map { "\($0.percentText) \($0.state.title)" } ?? "-")
                print("  DPI :", device.dpi.map { "\($0.displayText) 默认 \($0.defaultValue ?? 0) 范围 \($0.range.map { "\($0)" } ?? "-")" } ?? "-")
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
