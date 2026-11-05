import Foundation
import IOKit

/// 通用数据源：读取 IORegistry 中由系统维护的 `BatteryPercent` 属性。
/// 适用于妙控鼠标以及大多数通过蓝牙 HID 电量服务上报电量的第三方鼠标，但读不到 DPI。
@MainActor
final class BluetoothBatteryProvider: MouseDeviceProvider {
    let id = "system.battery"
    var displayName: String { L10n.text("系统蓝牙电量") }
    let priority = 10
    var onDevicesChanged: (() -> Void)?

    func start() {}
    func stop() {}

    func fetchDevices() async throws -> [MouseDevice] {
        var iterator: io_iterator_t = 0
        let matching = ["IOPropertyExistsMatch": "BatteryPercent"] as NSDictionary
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching as CFDictionary, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [String: MouseDevice] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let device = makeDevice(from: service) else { continue }
            // 同一设备可能在多个服务节点上都挂有 BatteryPercent
            results[device.id] = results[device.id] ?? device
        }
        return Array(results.values)
    }

    private func makeDevice(from service: io_service_t) -> MouseDevice? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any],
              let percent = properties["BatteryPercent"] as? Int,
              let name = properties["Product"] as? String,
              Self.isPointingDevice(properties: properties, name: name)
        else { return nil }

        let transport = (properties["Transport"] as? String) ?? ""
        let vendorID = properties["VendorID"] as? Int
        let productID = properties["ProductID"] as? Int
        let identity = (properties["SerialNumber"] as? String)
            ?? (properties["DeviceAddress"] as? String)
            ?? "\(vendorID ?? 0)-\(productID ?? 0)-\(name)"

        return MouseDevice(
            id: "\(id)-\(identity)",
            name: name,
            vendor: (properties["Manufacturer"] as? String) ?? Self.vendorName(for: vendorID),
            vendorID: vendorID,
            productID: productID,
            connection: transport.localizedCaseInsensitiveContains("bluetooth") ? .bluetooth
                : transport.localizedCaseInsensitiveContains("usb") ? .usb : .unknown,
            battery: BatteryStatus(percent: min(100, max(0, percent)), state: Self.chargeState(from: properties)),
            dpi: nil,
            providerID: id,
            protocolName: "HID Battery Service"
        )
    }

    private static func isPointingDevice(properties: [String: Any], name: String) -> Bool {
        let lowered = name.lowercased()
        if ["mouse", "trackpad", "trackball", "鼠标"].contains(where: lowered.contains) { return true }
        if properties["PrimaryUsagePage"] as? Int == 1, properties["PrimaryUsage"] as? Int == 2 { return true }
        let pairs = properties["DeviceUsagePairs"] as? [[String: Int]] ?? []
        return pairs.contains { $0["DeviceUsagePage"] == 1 && $0["DeviceUsage"] == 2 }
    }

    private static func chargeState(from properties: [String: Any]) -> BatteryStatus.ChargeState {
        if let charging = properties["BatteryIsCharging"] as? Bool {
            return charging ? .charging : .discharging
        }
        return .unknown
    }

    private static func vendorName(for vendorID: Int?) -> String {
        switch vendorID {
        case 0x004C, 0x05AC: "Apple"
        case 0x046D: "Logitech"
        case 0x1532: "Razer"
        case 0x1038: "SteelSeries"
        default: "Unknown Manufacturer"
        }
    }
}
