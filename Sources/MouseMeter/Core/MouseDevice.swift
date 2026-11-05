import Foundation

/// 一只鼠标在某一时刻的状态快照。由各个 `MouseDeviceProvider` 产出，UI 只依赖这个模型。
struct MouseDevice: Identifiable, Equatable, Sendable {
    /// 稳定标识，同一设备在多次刷新之间应保持不变（用于保留离线设备、记住菜单栏选中设备）。
    let id: String
    var name: String
    var vendor: String
    var vendorID: Int?
    var productID: Int?
    var connection: ConnectionKind
    var battery: BatteryStatus?
    var dpi: DPIStatus?
    /// 产出该设备的 provider 的 id
    var providerID: String
    /// 协议/数据来源的展示名，例如 "HID++ 4.2"
    var protocolName: String
    var isOnline: Bool = true
    var lastUpdated: Date = .now

    /// 用于跨 provider 去重的键。不同 provider 报告了同一个键时，保留优先级高的那个。
    var dedupeKey: String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

enum ConnectionKind: String, Sendable {
    case usb
    case bluetooth
    case receiver
    case unknown

    var title: String {
        switch self {
        case .usb: L10n.text("有线 USB")
        case .bluetooth: L10n.text("蓝牙")
        case .receiver: L10n.text("无线接收器")
        case .unknown: L10n.text("未知")
        }
    }

    var symbol: String {
        switch self {
        case .usb: "cable.connector"
        case .bluetooth: "dot.radiowaves.right"
        case .receiver: "antenna.radiowaves.left.and.right"
        case .unknown: "questionmark.circle"
        }
    }
}

struct BatteryStatus: Equatable, Sendable {
    enum ChargeState: Sendable {
        case discharging, charging, full, unknown

        var title: String {
            switch self {
            case .discharging: L10n.text("使用电池")
            case .charging: L10n.text("正在充电")
            case .full: L10n.text("已充满")
            case .unknown: L10n.text("状态未知")
            }
        }
    }

    /// 0...100
    var percent: Int
    var state: ChargeState
    /// 为 true 表示百分比是由电压或电量档位推算的近似值
    var isEstimated: Bool = false
    var voltage: Int? = nil

    var isCharging: Bool { state == .charging }
}

struct DPIStatus: Equatable, Sendable {
    var current: Int
    /// 仅当 Y 轴 DPI 与 X 轴不同时有值
    var currentY: Int? = nil
    var defaultValue: Int? = nil
    /// 传感器支持的 DPI 范围
    var range: ClosedRange<Int>? = nil
}
