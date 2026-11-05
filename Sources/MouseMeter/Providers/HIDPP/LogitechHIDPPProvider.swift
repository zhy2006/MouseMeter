import Foundation
import IOKit.hid

/// 罗技 HID++ 2.0 协议：支持 Unifying / Bolt / Lightspeed 接收器、有线直连与蓝牙直连的罗技鼠标。
/// 可读取电量（0x1000 / 0x1001 / 0x1004）和 DPI（0x2201 / 0x2202）。
@MainActor
final class LogitechHIDPPProvider: MouseDeviceProvider {
    let id = "logitech.hidpp"
    let displayName = "Logitech HID++ 2.0"
    let priority = 100
    var onDevicesChanged: (() -> Void)?

    private static let vendorID = 0x046D
    /// 0xFF00：USB 接收器 / 有线；0xFF43：蓝牙直连
    private static let usagePages = [0xFF00, 0xFF43]
    private static let directIndex: UInt8 = 0xFF
    private static let receiverSlots: ClosedRange<UInt8> = 1...6

    private var manager: IOHIDManager?
    private var channels: [IOHIDDevice: HIDPPChannel] = [:]
    /// 在 0xFF 和所有接收器槽位上都没有任何回应的接口（同一只鼠标常有多个厂商接口，只有一个说 HID++）
    private var silentChannels: Set<IOHIDDevice> = []
    private var devices: [String: HIDPPDevice] = [:]

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = Self.usagePages.map {
            [kIOHIDVendorIDKey: Self.vendorID, kIOHIDDeviceUsagePageKey: $0] as NSDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidppDeviceChangedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidppDeviceChangedCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        self.manager = manager
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        channels.values.forEach { $0.close() }
        channels.removeAll()
        devices.removeAll()
        silentChannels.removeAll()
        self.manager = nil
    }

    fileprivate func hidDevicesChanged() {
        onDevicesChanged?()
    }

    func fetchDevices() async throws -> [MouseDevice] {
        guard let manager else { return [] }
        let present = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        pruneChannels(keeping: present)

        var results: [MouseDevice] = []
        var claimed: Set<String> = []
        var permissionDenied = false

        let ordered = present.sorted { $0.intProperty(kIOHIDLocationIDKey) ?? 0 < $1.intProperty(kIOHIDLocationIDKey) ?? 0 }
        for hidDevice in ordered where !silentChannels.contains(hidDevice) {
            let channel = channels[hidDevice] ?? HIDPPChannel(device: hidDevice)
            channels[hidDevice] = channel

            let openResult = channel.open()
            if openResult == kIOReturnNotPermitted {
                permissionDenied = true
                continue
            }
            guard openResult == kIOReturnSuccess else { continue }

            let indices = await reachableIndices(on: channel)
            if indices == nil {
                silentChannels.insert(hidDevice)
                continue
            }

            for index in indices ?? [] {
                // 同一物理设备的多个接口共享 LocationID，只取第一个能读到数据的
                let claimKey = "\(channel.locationID)-\(index)"
                guard !claimed.contains(claimKey) else { continue }
                let device = hidppDevice(on: channel, index: index)
                if let snapshot = await snapshot(of: device) {
                    claimed.insert(claimKey)
                    results.append(snapshot)
                }
            }
        }

        if results.isEmpty, permissionDenied {
            throw ProviderError.inputMonitoringRequired
        }
        return results
    }

    // MARK: - 私有

    /// 返回能说 HID++ 2.0 的设备索引；接口完全无回应时返回 nil。
    private func reachableIndices(on channel: HIDPPChannel) async -> [UInt8]? {
        var anyResponse = false
        let direct = hidppDevice(on: channel, index: Self.directIndex)
        do {
            if try await direct.ping().major >= 2 { return [Self.directIndex] }
            anyResponse = true
        } catch HIDPPError.deviceError {
            anyResponse = true // 接收器会对 0xFF 回 HID++ 1.0 错误，继续探测配对槽位
        } catch {}

        var indices: [UInt8] = []
        for slot in Self.receiverSlots {
            let device = hidppDevice(on: channel, index: slot)
            do {
                if try await device.ping().major >= 2 { indices.append(slot) }
                anyResponse = true
            } catch HIDPPError.deviceError {
                anyResponse = true // 空槽位或设备休眠
            } catch {}
        }
        return anyResponse ? indices : nil
    }

    private func snapshot(of device: HIDPPDevice) async -> MouseDevice? {
        do {
            let kind = try await device.kind()
            if let kind, !kind.isPointingDevice { return nil }
            let dpi = try? await device.dpi()
            // 没有 0x0005 又没有 DPI 功能的，多半不是鼠标
            if kind == nil, dpi == nil { return nil }
            let battery = try? await device.battery()
            let name = try await device.name() ?? device.channel.productName ?? "Logitech Device"

            let channel = device.channel
            let connection: ConnectionKind
            if device.index != Self.directIndex {
                connection = .receiver
            } else if channel.transport?.localizedCaseInsensitiveContains("bluetooth") == true {
                connection = .bluetooth
            } else {
                connection = .usb
            }

            let version = device.protocolVersion.map { "HID++ \($0.major).\($0.minor)" } ?? "HID++ 2.0"
            return MouseDevice(
                id: "\(id)-\(channel.locationID)-\(device.index)",
                name: name,
                vendor: "Logitech",
                vendorID: Self.vendorID,
                productID: channel.device.intProperty(kIOHIDProductIDKey),
                connection: connection,
                battery: battery,
                dpi: dpi,
                providerID: id,
                protocolName: version
            )
        } catch {
            return nil
        }
    }

    private func hidppDevice(on channel: HIDPPChannel, index: UInt8) -> HIDPPDevice {
        let key = "\(ObjectIdentifier(channel))-\(index)"
        if let device = devices[key] { return device }
        let device = HIDPPDevice(channel: channel, index: index)
        devices[key] = device
        return device
    }

    private func pruneChannels(keeping present: Set<IOHIDDevice>) {
        for (hidDevice, channel) in channels where !present.contains(hidDevice) {
            channel.close()
            channels[hidDevice] = nil
            let prefix = "\(ObjectIdentifier(channel))-"
            devices = devices.filter { !$0.key.hasPrefix(prefix) }
        }
        silentChannels.formIntersection(present)
    }
}

private func hidppDeviceChangedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let provider = Unmanaged<LogitechHIDPPProvider>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        provider.hidDevicesChanged()
    }
}
