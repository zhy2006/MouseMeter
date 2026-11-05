import Foundation
import UserNotifications

/// 汇总所有 provider 的结果，定时刷新，并向 UI 发布设备列表。
@MainActor
final class DeviceMonitor: ObservableObject {
    @Published private(set) var devices: [MouseDevice] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var needsInputMonitoringPermission = false

    let providers: [any MouseDeviceProvider]

    private var loopTask: Task<Void, Never>?
    private var pendingRefresh: Task<Void, Never>?
    private var refreshQueued = false
    private var alertedDeviceIDs: Set<String> = []
    private let defaults = UserDefaults.standard

    init(providers: [any MouseDeviceProvider]) {
        self.providers = providers.sorted { $0.priority > $1.priority }
    }

    func start() {
        for provider in providers {
            provider.onDevicesChanged = { [weak self] in self?.scheduleRefresh(after: .seconds(1)) }
            provider.start()
        }
        restartPolling()
    }

    /// 刷新间隔改变后调用
    func restartPolling() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.defaults.double(forKey: SettingsKey.refreshInterval) ?? 60
                try? await Task.sleep(for: .seconds(max(5, interval)))
            }
        }
    }

    /// 设备插拔时会连续触发多次回调，合并成一次刷新
    func scheduleRefresh(after delay: Duration) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshQueued = false
            await performRefresh()
        } while refreshQueued
    }

    /// 移除一个离线设备的记录
    func forget(_ device: MouseDevice) {
        devices.removeAll { $0.id == device.id }
    }

    /// 菜单栏展示的设备：用户指定的 > 第一个在线且有电量的 > 第一个在线的 > 第一个
    func menuBarDevice(preferredID: String) -> MouseDevice? {
        if !preferredID.isEmpty, let device = devices.first(where: { $0.id == preferredID }) {
            return device
        }
        return devices.first { $0.isOnline && $0.battery != nil }
            ?? devices.first { $0.isOnline }
            ?? devices.first
    }

    // MARK: - 私有

    private func performRefresh() async {
        var fresh: [MouseDevice] = []
        var claimedKeys: [String: String] = [:] // dedupeKey → providerID
        var permissionRequired = false

        for provider in providers {
            let found: [MouseDevice]
            do {
                found = try await provider.fetchDevices()
            } catch ProviderError.inputMonitoringRequired {
                permissionRequired = true
                continue
            } catch {
                continue
            }
            for device in found {
                // 只在不同 provider 之间去重：同一 provider 内两只同名鼠标都应保留
                if let owner = claimedKeys[device.dedupeKey], owner != provider.id { continue }
                claimedKeys[device.dedupeKey] = provider.id
                fresh.append(device)
            }
        }

        let freshIDs = Set(fresh.map(\.id))
        let offline = devices
            .filter { !freshIDs.contains($0.id) }
            .map { device -> MouseDevice in
                var device = device
                device.isOnline = false
                return device
            }

        devices = (fresh + offline).sorted {
            if $0.isOnline != $1.isOnline { return $0.isOnline }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        needsInputMonitoringPermission = permissionRequired && fresh.isEmpty
        lastRefresh = .now
        evaluateLowBatteryAlerts()
    }

    private func evaluateLowBatteryAlerts() {
        guard defaults.bool(forKey: SettingsKey.lowBatteryAlertEnabled) else { return }
        let threshold = defaults.integer(forKey: SettingsKey.lowBatteryThreshold)

        for device in devices where device.isOnline {
            guard let battery = device.battery else { continue }
            if battery.state == .charging || battery.state == .full || battery.percent > threshold + 5 {
                alertedDeviceIDs.remove(device.id)
            } else if battery.percent <= threshold, !alertedDeviceIDs.contains(device.id) {
                alertedDeviceIDs.insert(device.id)
                Notifier.post(
                    title: "\(device.name) 电量低",
                    body: "剩余 \(battery.percent)%，请及时充电。"
                )
            }
        }
    }
}

enum Notifier {
    /// 通过 `swift run` 直接运行时没有 bundle，UNUserNotificationCenter 会崩溃，需要跳过
    private static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
