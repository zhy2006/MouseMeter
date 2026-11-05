import Foundation
import IOKit.hid

enum HIDPPError: Error {
    case timeout
    case busy
    case io(IOReturn)
    /// 设备返回了错误报告。`hidpp10` 为 true 表示 HID++ 1.0 错误（0x8F），通常意味着该槽位无设备。
    case deviceError(code: UInt8, hidpp10: Bool)
}

/// 一个 IOHIDDevice（罗技厂商自定义接口，usage page 0xFF00 / 0xFF43）上的 HID++ 请求/响应通道。
///
/// 所有 IOKit 回调都调度在主 RunLoop 上，因此该类型整体隔离在 MainActor。
/// 同一时刻只允许一个请求在途，调用方负责串行化（DeviceMonitor 保证刷新不会并发）。
@MainActor
final class HIDPPChannel {
    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    private static let inputBufferSize = 64

    let device: IOHIDDevice
    let locationID: Int
    let transport: String?
    let productName: String?
    private(set) var isOpen = false

    private let useLongReports: Bool
    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private var pending: PendingRequest?
    private var requestCounter = 0
    private var nextSoftwareID: UInt8 = 1

    private struct PendingRequest {
        let token: Int
        let deviceIndex: UInt8
        let featureIndex: UInt8
        let functionAndSoftwareID: UInt8
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    init(device: IOHIDDevice) {
        self.device = device
        locationID = device.intProperty(kIOHIDLocationIDKey) ?? 0
        transport = device.stringProperty(kIOHIDTransportKey)
        productName = device.stringProperty(kIOHIDProductKey)
        useLongReports = (device.intProperty(kIOHIDMaxOutputReportSizeKey) ?? 20) >= 20
        inputBuffer = .allocate(capacity: Self.inputBufferSize)
    }

    deinit {
        inputBuffer.deallocate()
    }

    func open() -> IOReturn {
        guard !isOpen else { return kIOReturnSuccess }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return result }
        IOHIDDeviceRegisterInputReportCallback(
            device, inputBuffer, Self.inputBufferSize, hidppInputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        isOpen = true
        return kIOReturnSuccess
    }

    /// 必须在释放前调用，否则 IOKit 回调会持有悬空指针。
    func close() {
        guard isOpen else { return }
        isOpen = false
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, Self.inputBufferSize, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if let pending {
            finish(token: pending.token, with: .failure(HIDPPError.io(kIOReturnNotOpen)))
        }
    }

    /// 发送一个 HID++ 2.0 请求，返回响应报告中的参数部分（第 4 字节之后）。
    func request(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        function: UInt8,
        params: [UInt8] = [],
        timeout: Duration = .milliseconds(1200)
    ) async throws -> [UInt8] {
        guard isOpen else { throw HIDPPError.io(kIOReturnNotOpen) }
        guard pending == nil else { throw HIDPPError.busy }

        // software id 取 1...15，用来区分我们的响应和设备主动发出的通知（通知的 software id 为 0）
        let softwareID = nextSoftwareID
        nextSoftwareID = nextSoftwareID % 15 + 1
        let functionAndSoftwareID = (function << 4) | softwareID

        var report = [UInt8](repeating: 0, count: useLongReports ? 20 : 7)
        report[0] = useLongReports ? Self.longReportID : Self.shortReportID
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = functionAndSoftwareID
        for (offset, byte) in params.prefix(report.count - 4).enumerated() {
            report[4 + offset] = byte
        }

        requestCounter += 1
        let token = requestCounter

        return try await withCheckedThrowingContinuation { continuation in
            pending = PendingRequest(
                token: token,
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                functionAndSoftwareID: functionAndSoftwareID,
                continuation: continuation
            )
            let result = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), $0.baseAddress!, $0.count)
            }
            guard result == kIOReturnSuccess else {
                finish(token: token, with: .failure(HIDPPError.io(result)))
                return
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(token: token, with: .failure(HIDPPError.timeout))
            }
        }
    }

    fileprivate func handleInputReport(_ report: [UInt8]) {
        // 输入缓冲区的第 0 字节就是 report id
        guard report.count >= 7, let pending, report[1] == pending.deviceIndex else { return }

        if report[2] == pending.featureIndex, report[3] == pending.functionAndSoftwareID {
            finish(token: pending.token, with: .success(Array(report.dropFirst(4))))
        } else if report[2] == 0xFF || report[2] == 0x8F,
                  report[3] == pending.featureIndex,
                  report[4] == pending.functionAndSoftwareID {
            let error = HIDPPError.deviceError(code: report[5], hidpp10: report[2] == 0x8F)
            finish(token: pending.token, with: .failure(error))
        }
    }

    private func finish(token: Int, with result: Result<[UInt8], Error>) {
        guard let pending, pending.token == token else { return }
        self.pending = nil
        pending.continuation.resume(with: result)
    }
}

private func hidppInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    length: CFIndex
) {
    guard let context, length > 0 else { return }
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    let channel = Unmanaged<HIDPPChannel>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        channel.handleInputReport(bytes)
    }
}

extension IOHIDDevice {
    func intProperty(_ key: String) -> Int? {
        IOHIDDeviceGetProperty(self, key as CFString) as? Int
    }

    func stringProperty(_ key: String) -> String? {
        IOHIDDeviceGetProperty(self, key as CFString) as? String
    }
}
