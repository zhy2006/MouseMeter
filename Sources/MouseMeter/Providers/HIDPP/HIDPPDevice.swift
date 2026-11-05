import Foundation

/// HID++ 2.0 功能（feature）编号。
enum HIDPPFeature {
    static let root: UInt16 = 0x0000
    static let deviceNameAndType: UInt16 = 0x0005
    static let batteryStatus: UInt16 = 0x1000
    static let batteryVoltage: UInt16 = 0x1001
    static let unifiedBattery: UInt16 = 0x1004
    static let adjustableDPI: UInt16 = 0x2201
    static let extendedAdjustableDPI: UInt16 = 0x2202
}

/// HID++ 通道上某个设备索引（0xFF 为直连设备，1...6 为接收器上的配对槽位）对应的一台设备。
/// 实例会在多次刷新之间复用，以缓存 feature index、名称等不变信息。
@MainActor
final class HIDPPDevice {
    enum Kind: UInt8 {
        case keyboard = 0, remoteControl, numpad, mouse, trackpad, trackball, presenter, receiver

        var isPointingDevice: Bool { self == .mouse || self == .trackpad || self == .trackball }
    }

    let channel: HIDPPChannel
    let index: UInt8
    private(set) var protocolVersion: (major: UInt8, minor: UInt8)?

    private var featureIndices: [UInt16: UInt8] = [:]
    private var missingFeatures: Set<UInt16> = []
    private var cachedName: String?
    private var cachedKind: Kind??

    init(channel: HIDPPChannel, index: UInt8) {
        self.channel = channel
        self.index = index
    }

    // MARK: - 基础

    /// Root.getProtocolVersion。HID++ 1.0 设备 / 空槽位会抛出 `HIDPPError.deviceError`。
    @discardableResult
    func ping() async throws -> (major: UInt8, minor: UInt8) {
        let reply = try await channel.request(deviceIndex: index, featureIndex: 0, function: 1, params: [0, 0, 0x5A])
        let version = (major: reply[0], minor: reply[1])
        protocolVersion = version
        return version
    }

    func featureIndex(of feature: UInt16) async throws -> UInt8? {
        if let index = featureIndices[feature] { return index }
        if missingFeatures.contains(feature) { return nil }
        let reply = try await channel.request(
            deviceIndex: index, featureIndex: 0, function: 0,
            params: [UInt8(feature >> 8), UInt8(feature & 0xFF)]
        )
        guard reply[0] != 0 else {
            missingFeatures.insert(feature)
            return nil
        }
        featureIndices[feature] = reply[0]
        return reply[0]
    }

    /// 调用某个 feature 的函数；设备不支持该 feature 时返回 nil。
    func call(_ feature: UInt16, function: UInt8, params: [UInt8] = []) async throws -> [UInt8]? {
        guard let featureIndex = try await featureIndex(of: feature) else { return nil }
        return try await channel.request(deviceIndex: index, featureIndex: featureIndex, function: function, params: params)
    }

    // MARK: - 0x0005 Device Name & Type

    func kind() async throws -> Kind? {
        if let cachedKind { return cachedKind }
        let reply = try await call(HIDPPFeature.deviceNameAndType, function: 2)
        let kind = reply.flatMap { Kind(rawValue: $0[0]) }
        cachedKind = .some(kind)
        return kind
    }

    func name() async throws -> String? {
        if let cachedName { return cachedName }
        guard let countReply = try await call(HIDPPFeature.deviceNameAndType, function: 0) else { return nil }
        let length = Int(countReply[0])
        var bytes: [UInt8] = []
        while bytes.count < length {
            guard let chunk = try await call(HIDPPFeature.deviceNameAndType, function: 1, params: [UInt8(bytes.count)]) else { break }
            let taken = chunk.prefix(length - bytes.count)
            if taken.isEmpty { break }
            bytes += taken
        }
        let name = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        cachedName = name.isEmpty ? nil : name
        return cachedName
    }

    // MARK: - 电量（0x1004 → 0x1000 → 0x1001）

    func battery() async throws -> BatteryStatus? {
        if let status = try await unifiedBattery() { return status }
        if let status = try await batteryStatus() { return status }
        return try await batteryVoltage()
    }

    private func unifiedBattery() async throws -> BatteryStatus? {
        guard let capabilities = try await call(HIDPPFeature.unifiedBattery, function: 0),
              let reply = try await call(HIDPPFeature.unifiedBattery, function: 1) else { return nil }
        let supportsStateOfCharge = capabilities[1] & 0x02 != 0

        let state: BatteryStatus.ChargeState = switch reply[2] {
        case 0: .discharging
        case 1, 2: .charging
        case 3: .full
        default: .unknown
        }

        if supportsStateOfCharge {
            return BatteryStatus(percent: clampPercent(reply[0]), state: state)
        }
        // 只支持档位：1=critical 2=low 4=good 8=full
        let level = reply[1]
        let percent = level & 0x08 != 0 ? 90 : level & 0x04 != 0 ? 50 : level & 0x02 != 0 ? 20 : 5
        return BatteryStatus(percent: percent, state: state, isEstimated: true)
    }

    private func batteryStatus() async throws -> BatteryStatus? {
        guard let reply = try await call(HIDPPFeature.batteryStatus, function: 0) else { return nil }
        let state: BatteryStatus.ChargeState = switch reply[2] {
        case 0: .discharging
        case 1, 2, 4: .charging
        case 3: .full
        default: .unknown
        }
        return BatteryStatus(percent: state == .full ? 100 : clampPercent(reply[0]), state: state)
    }

    private func batteryVoltage() async throws -> BatteryStatus? {
        guard let reply = try await call(HIDPPFeature.batteryVoltage, function: 0) else { return nil }
        let millivolts = reply.uint16(at: 0)
        let flags = reply[2]
        let state: BatteryStatus.ChargeState
        if flags & 0x80 != 0 {
            state = (flags & 0x07) == 1 ? .full : .charging
        } else {
            state = .discharging
        }
        return BatteryStatus(
            percent: Self.percent(forMillivolts: millivolts),
            state: state,
            isEstimated: true,
            voltage: millivolts
        )
    }

    /// 罗技锂电池放电曲线的粗略近似。
    private static let voltageCurve: [(mv: Int, percent: Int)] = [
        (4186, 100), (4067, 90), (3989, 80), (3922, 70), (3870, 60), (3828, 50),
        (3797, 40), (3770, 30), (3741, 20), (3702, 10), (3500, 0),
    ]

    static func percent(forMillivolts mv: Int) -> Int {
        guard let first = voltageCurve.first, let last = voltageCurve.last else { return 0 }
        if mv >= first.mv { return 100 }
        if mv <= last.mv { return 0 }
        for (upper, lower) in zip(voltageCurve, voltageCurve.dropFirst()) where mv >= lower.mv {
            let ratio = Double(mv - lower.mv) / Double(upper.mv - lower.mv)
            return lower.percent + Int((ratio * Double(upper.percent - lower.percent)).rounded())
        }
        return 0
    }

    // MARK: - DPI（0x2202 → 0x2201）

    func dpi() async throws -> DPIStatus? {
        if let status = try await extendedDPI() { return status }
        return try await adjustableDPI()
    }

    private func extendedDPI() async throws -> DPIStatus? {
        // getSensorDpiParameters(sensor 0) → [sensor, x(2), defaultX(2), y(2), defaultY(2), lod]
        guard let reply = try await call(HIDPPFeature.extendedAdjustableDPI, function: 5, params: [0]) else { return nil }
        let x = reply.uint16(at: 1)
        let y = reply.uint16(at: 5)
        let defaultX = reply.uint16(at: 3)

        // getSensorDpiRanges(sensor 0, direction X, page n) → [sensor, direction, page, data...]
        // 每页 13 字节数据，16 位值会跨页，必须拼接后再解析
        var data: [UInt8] = []
        var values: [Int] = []
        for page in UInt8(0)..<8 {
            guard let rangeReply = try? await call(HIDPPFeature.extendedAdjustableDPI, function: 2, params: [0, 0, page]) else { break }
            data += rangeReply.dropFirst(3)
            let parsed = Self.parseDPIValues(data)
            values = parsed.values
            if parsed.terminated { break }
        }

        return DPIStatus(
            current: x,
            currentY: y != 0 && y != x ? y : nil,
            defaultValue: defaultX == 0 ? nil : defaultX,
            range: Self.range(of: values)
        )
    }

    private func adjustableDPI() async throws -> DPIStatus? {
        // getSensorDpi(sensor 0) → [sensor, dpi(2), default(2)]
        guard let reply = try await call(HIDPPFeature.adjustableDPI, function: 2, params: [0]) else { return nil }
        let current = reply.uint16(at: 1)
        let defaultValue = reply.uint16(at: 3)
        var range: ClosedRange<Int>?
        if let list = try? await call(HIDPPFeature.adjustableDPI, function: 1, params: [0]) {
            range = Self.range(of: Self.parseDPIValues(Array(list.dropFirst())).values)
        }
        return DPIStatus(current: current, defaultValue: defaultValue == 0 ? nil : defaultValue, range: range)
    }

    /// DPI 列表为大端 16 位值，0 结尾；最高 3 位为 111 的值表示「步进」，夹在两个 DPI 值之间。
    static func parseDPIValues(_ bytes: [UInt8]) -> (values: [Int], terminated: Bool) {
        var values: [Int] = []
        var offset = 0
        while offset + 1 < bytes.count {
            let value = bytes.uint16(at: offset)
            offset += 2
            if value == 0 { return (values, true) }
            if value >> 13 == 0b111 { continue }
            values.append(value)
        }
        return (values, false)
    }

    private static func range(of values: [Int]) -> ClosedRange<Int>? {
        guard let low = values.min(), let high = values.max(), low < high else { return nil }
        return low...high
    }

    private func clampPercent(_ value: UInt8) -> Int {
        min(100, max(0, Int(value)))
    }
}

extension Array where Element == UInt8 {
    /// 大端 16 位读取，越界返回 0（短报告只有 3 字节参数）。
    func uint16(at offset: Int) -> Int {
        guard offset >= 0, offset + 1 < count else { return 0 }
        return Int(self[offset]) << 8 | Int(self[offset + 1])
    }
}
