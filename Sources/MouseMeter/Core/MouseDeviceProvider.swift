import Foundation

/// 鼠标数据源协议。
///
/// 每种鼠标通信协议（罗技 HID++、通用蓝牙电量、雷蛇、赛睿……）实现一个 provider，
/// 然后在 `ProviderRegistry.makeDefault()` 中注册即可，UI 与刷新逻辑无需改动。
@MainActor
protocol MouseDeviceProvider: AnyObject {
    /// 唯一标识，例如 "logitech.hidpp"
    var id: String { get }
    /// 展示名，例如 "Logitech HID++ 2.0"
    var displayName: String { get }
    /// 多个 provider 报告同一设备时，数值大的胜出（能读到 DPI 的专有协议应高于通用协议）
    var priority: Int { get }
    /// 设备插拔等事件发生时由 provider 调用，通知监视器尽快刷新
    var onDevicesChanged: (() -> Void)? { get set }

    /// 开始监听（注册 IOKit 回调等）。只会被调用一次。
    func start()
    func stop()
    /// 读取当前连接的鼠标。找不到设备时返回空数组；需要用户操作（如授权）时抛出 `ProviderError`。
    func fetchDevices() async throws -> [MouseDevice]
}

enum ProviderError: Error, Equatable {
    /// 需要在「系统设置 › 隐私与安全性 › 输入监控」中授权
    case inputMonitoringRequired
    case failed(String)
}

enum ProviderRegistry {
    /// 新协议在这里注册。
    @MainActor
    static func makeDefault() -> [any MouseDeviceProvider] {
        [
            LogitechHIDPPProvider(),
            BluetoothBatteryProvider(),
        ]
    }
}
