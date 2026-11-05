import SwiftUI

/// 菜单栏上的图标 + 文字。
///
/// MenuBarExtra 的 label 只会取出其中的 Image / Text，自定义绘制的电池图标会丢失，
/// 所以先用 ImageRenderer 渲染成模板图片，再交给菜单栏，这样深浅色菜单栏都能自动适配。
struct MenuBarLabel: View {
    @EnvironmentObject private var monitor: DeviceMonitor
    @AppStorage(SettingsKey.menuBarShowsPercent) private var showsPercent = true
    @AppStorage(SettingsKey.menuBarShowsDPI) private var showsDPI = false
    @AppStorage(SettingsKey.menuBarDeviceID) private var deviceID = ""
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let device = monitor.menuBarDevice(preferredID: deviceID)
        Image(nsImage: render(MenuBarLabelContent(device: device, showsPercent: showsPercent, showsDPI: showsDPI)))
            .accessibilityLabel(accessibilityText(for: device))
    }

    private func render(_ content: MenuBarLabelContent) -> NSImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = max(displayScale, 2)
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }

    private func accessibilityText(for device: MouseDevice?) -> String {
        guard let device else { return L10n.text("MouseMeter：未发现鼠标") }
        if let battery = device.battery { return L10n.format("battery_accessibility", device.name, battery.percent) }
        return device.name
    }
}

private struct MenuBarLabelContent: View {
    var device: MouseDevice?
    var showsPercent: Bool
    var showsDPI: Bool

    var body: some View {
        HStack(spacing: 4) {
            if let device, let battery = device.battery {
                BatteryGlyph(percent: battery.percent, isCharging: battery.isCharging, height: 10.5)
                if showsPercent {
                    Text("\(battery.percent)%")
                }
            } else {
                Image(systemName: device == nil ? "computermouse" : "computermouse.fill")
                    .font(.system(size: 13, weight: .regular))
                if device == nil, showsPercent {
                    Text("--")
                }
            }
            if showsDPI, let dpi = device?.dpi {
                Text("\(dpi.current)")
                    .foregroundStyle(.primary.opacity(0.75))
            }
        }
        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
        .opacity(device?.isOnline == false ? 0.5 : 1)
        .foregroundStyle(.black)
        .padding(.vertical, 1)
        .environment(\.colorScheme, .light)
    }
}
