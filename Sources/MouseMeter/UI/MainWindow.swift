import SwiftUI

enum SidebarItem: Hashable {
    case device(String)
    case settings
}

@MainActor
final class AppNavigation: ObservableObject {
    static let mainWindowID = "main"
    @Published var selection: SidebarItem?
}

struct MainWindowView: View {
    @EnvironmentObject private var monitor: DeviceMonitor
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                Section("设备") {
                    if monitor.devices.isEmpty {
                        Text("暂无设备").foregroundStyle(.tertiary)
                    }
                    ForEach(monitor.devices) { device in
                        SidebarDeviceRow(device: device)
                            .tag(SidebarItem.device(device.id))
                            .contextMenu {
                                if !device.isOnline {
                                    Button("移除此离线设备") { monitor.forget(device) }
                                }
                            }
                    }
                }
                Section("通用") {
                    Label("设置", systemImage: "gearshape").tag(SidebarItem.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { RefreshButton() }
                }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            if navigation.selection == nil {
                navigation.selection = monitor.devices.first.map { .device($0.id) } ?? .settings
            }
            // 主窗口打开时显示在 Dock 和 ⌘Tab 中，关闭后回到纯菜单栏应用
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
        .onChange(of: monitor.devices.map(\.id)) { _, ids in
            if case .device(let id) = navigation.selection, !ids.contains(id) {
                navigation.selection = ids.first.map { .device($0) } ?? .settings
            } else if navigation.selection == nil, let first = ids.first {
                navigation.selection = .device(first)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection {
        case .device(let id):
            if let device = monitor.devices.first(where: { $0.id == id }) {
                DeviceDetailView(device: device)
            } else {
                EmptyDevicesView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .settings:
            SettingsView()
        case nil:
            EmptyDevicesView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SidebarDeviceRow: View {
    var device: MouseDevice

    var body: some View {
        HStack(spacing: 10) {
            DeviceAvatar(device: device, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).lineLimit(1)
                Text(device.isOnline ? device.connection.title : "离线")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let battery = device.battery {
                Text("\(battery.percent)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(battery.tint)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DeviceDetailView: View {
    var device: MouseDevice

    var body: some View {
        ScrollView {
            DeviceDetailContent(device: device)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.06), .clear],
                startPoint: .top, endPoint: .center
            )
        )
        .navigationTitle(device.name)
        .animation(.default, value: device)
    }
}

struct DeviceDetailContent: View {
    var device: MouseDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            HStack(alignment: .top, spacing: 20) {
                batteryCard
                dpiCard
            }
            .fixedSize(horizontal: false, vertical: true)

            infoCard
        }
        .padding(28)
    }

    private var header: some View {
        HStack(spacing: 16) {
            DeviceAvatar(device: device, size: 60)
            VStack(alignment: .leading, spacing: 6) {
                Text(device.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    Pill(text: device.vendor, symbol: "building.2")
                    Pill(text: device.connection.title, symbol: device.connection.symbol, tint: .blue)
                    if device.isOnline {
                        Pill(text: "在线", symbol: "circle.fill", tint: .green)
                    } else {
                        Pill(text: "离线 · 显示上次读数", symbol: "moon.zzz.fill", tint: .orange)
                    }
                }
            }
            Spacer()
        }
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(title: "电量", symbol: "battery.100percent")
            VStack(spacing: 14) {
                BatteryRing(battery: device.battery, size: 130, lineWidth: 12)
                VStack(spacing: 4) {
                    if let battery = device.battery {
                        Label(battery.state.title, systemImage: battery.isCharging ? "bolt.fill" : "leaf.fill")
                            .font(.headline)
                            .foregroundStyle(battery.tint)
                        if battery.isEstimated {
                            Text("设备只上报电压或电量档位，百分比为估算值")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let voltage = battery.voltage {
                            Text("电压 \(String(format: "%.2f", Double(voltage) / 1000)) V")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(device.connection == .usb ? "有线供电" : "未读取到电量")
                            .font(.headline)
                        Text(device.connection == .usb ? "该设备没有电池或未上报电量" : "当前协议不支持读取电量")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .card()
    }

    private var dpiCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(title: "DPI", symbol: "scope")
            if let dpi = device.dpi {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(dpi.displayText)
                        .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("DPI")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let defaultValue = dpi.defaultValue {
                    Text("默认 \(defaultValue) DPI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DPIRangeBar(dpi: dpi)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Image(systemName: "scope")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("当前协议无法读取 DPI")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "设备信息", symbol: "info.circle")
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                infoRow("厂商", device.vendor)
                if let vendorID = device.vendorID {
                    infoRow("VID / PID", String(format: "%04X / %04X", vendorID, device.productID ?? 0))
                }
                infoRow("连接方式", device.connection.title)
                infoRow("数据来源", device.protocolName)
                infoRow("最近读取", device.lastUpdated.formatted(date: .abbreviated, time: .standard))
            }
            .font(.callout)
        }
        .card()
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
