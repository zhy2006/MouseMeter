import SwiftUI

/// 点击菜单栏图标后弹出的面板
struct MenuBarPanel: View {
    @EnvironmentObject private var monitor: DeviceMonitor
    @EnvironmentObject private var navigation: AppNavigation
    @EnvironmentObject private var updater: UpdateManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if monitor.devices.isEmpty {
                EmptyDevicesView(compact: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(monitor.devices) { device in
                        Button {
                            open(.device(device.id))
                        } label: {
                            PanelDeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let update = updater.availableUpdate {
                Divider()
                Button {
                    open(.settings)
                } label: {
                    Label(L10n.format("update_available", update.version), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "computermouse.fill")
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
            Text("MouseMeter").font(.headline)
            Spacer()
            RefreshButton()
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            if let lastRefresh = monitor.lastRefresh {
                Text(L10n.format("updated_at", lastRefresh.formatted(.dateTime.hour().minute().locale(L10n.locale))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            footerButton(L10n.text("打开主界面"), symbol: "macwindow") { open(navigation.selection ?? defaultSelection) }
            footerButton(L10n.text("设置"), symbol: "gearshape") { open(.settings) }
            footerButton(L10n.text("退出"), symbol: "power") { NSApp.terminate(nil) }
        }
    }

    private var defaultSelection: SidebarItem {
        monitor.devices.first.map { .device($0.id) } ?? .settings
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    private func open(_ item: SidebarItem) {
        navigation.selection = item
        openWindow(id: AppNavigation.mainWindowID)
        NSApp.activate()
    }
}

private struct PanelDeviceRow: View {
    var device: MouseDevice
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            DeviceAvatar(device: device, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(device.isOnline ? device.connection.title : L10n.text("离线"), systemImage: device.isOnline ? device.connection.symbol : "moon.zzz")
                    if let dpi = device.dpi {
                        Text("·")
                        Text("\(dpi.displayText) DPI")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let battery = device.battery {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(battery.percentText)
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(battery.tint)
                    BatteryGlyph(percent: battery.percent, isCharging: battery.isCharging, height: 9, fill: battery.tint)
                }
            } else {
                Image(systemName: "powerplug")
                    .foregroundStyle(.tertiary)
                    .help(L10n.text("未读取到电量"))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
        )
        .opacity(device.isOnline ? 1 : 0.6)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

struct RefreshButton: View {
    @EnvironmentObject private var monitor: DeviceMonitor

    var body: some View {
        Button {
            Task { await monitor.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate, isActive: monitor.isRefreshing)
        }
        .buttonStyle(.borderless)
        .disabled(monitor.isRefreshing)
        .help(L10n.text("立即刷新"))
    }
}

/// 没有发现设备时的占位，包括「需要输入监控权限」的提示
struct EmptyDevicesView: View {
    @EnvironmentObject private var monitor: DeviceMonitor
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 14) {
            Image(systemName: monitor.needsInputMonitoringPermission ? "lock.shield" : "computermouse")
                .font(.system(size: compact ? 28 : 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text(monitor.needsInputMonitoringPermission ? L10n.text("需要输入监控权限") : L10n.text("未发现支持的鼠标"))
                .font(compact ? .headline : .title3.weight(.semibold))
            Text(monitor.needsInputMonitoringPermission
                 ? L10n.text("请在「系统设置 › 隐私与安全性 › 输入监控」中允许 MouseMeter，然后重新打开应用。")
                 : L10n.text("请确认鼠标已开机并已连接（接收器、蓝牙或有线）。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if monitor.needsInputMonitoringPermission {
                Button(L10n.text("打开系统设置")) {
                    PermissionHelper.requestInputMonitoring()
                }
                .controlSize(compact ? .small : .regular)
            }
        }
    }
}
