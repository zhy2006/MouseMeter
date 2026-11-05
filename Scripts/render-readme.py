#!/usr/bin/env python3
"""Render README screenshots from the real SwiftUI views with synthetic data."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
output = root / 'docs' / 'images'
output.mkdir(parents=True, exist_ok=True)
renderer = r'''
import AppKit
import SwiftUI

@MainActor
final class SampleProvider: MouseDeviceProvider {
    let id = "readme.samples"
    let displayName = "Demo"
    let priority = 1
    var onDevicesChanged: (() -> Void)?
    func start() {}
    func stop() {}
    func fetchDevices() async throws -> [MouseDevice] {
        let date = Date(timeIntervalSince1970: 1_767_268_800)
        return [
            MouseDevice(id: "demo-wireless", name: L10n.language == .simplifiedChinese ? "示例无线鼠标" : "Demo Wireless Mouse", vendor: "Logitech",
                vendorID: 0x046D, productID: 0x0000, connection: .receiver,
                battery: BatteryStatus(percent: 78, state: .discharging),
                dpi: DPIStatus(current: 1600, defaultValue: 800, range: 100...25600),
                providerID: id, protocolName: "HID++ 2.0", lastUpdated: date),
            MouseDevice(id: "demo-bluetooth", name: L10n.language == .simplifiedChinese ? "示例蓝牙鼠标" : "Demo Bluetooth Mouse", vendor: "Apple",
                connection: .bluetooth, battery: BatteryStatus(percent: 56, state: .discharging),
                providerID: id, protocolName: "Bluetooth", lastUpdated: date)
        ]
    }
}

// A synthetic macOS desktop context; the MouseMeter label and panel reuse app views.
struct MenuBarScene: View {
    let device: MouseDevice
    var chinese: Bool { L10n.language == .simplifiedChinese }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                Image(systemName: "apple.logo").font(.system(size: 17))
                Text(chinese ? "访达" : "Finder").bold()
                ForEach(chinese ? ["文件", "编辑", "显示", "前往", "窗口", "帮助"] : ["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { title in
                    Text(title)
                }
                Spacer()
                MenuBarLabelContent(device: device, showsPercent: true, showsDPI: true)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                Image(systemName: "wifi")
                Image(systemName: "magnifyingglass")
                Image(systemName: "switch.2")
                Text(chinese ? "1月1日 周四 20:00" : "Thu Jan 1  8:00 PM")
            }
            .font(.system(size: 13))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 24)
            .frame(height: 36)
            .background(.white.opacity(0.72))

            HStack {
                Spacer()
                MenuBarPanel()
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.7)))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
                    .padding(.trailing, 235)
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(width: 1440, height: 400)
        .background(LinearGradient(colors: [Color(red: 0.29, green: 0.40, blue: 0.75), Color(red: 0.63, green: 0.63, blue: 0.87), Color(red: 0.88, green: 0.73, blue: 0.81)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, .light)
    }
}

@main
struct ReadmeRenderer {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        SettingsKey.registerDefaults()
        // Registration defaults affect this process only; never change saved preferences.
        UserDefaults.standard.register(defaults: [SettingsKey.language: CommandLine.arguments[1]])
        app.appearance = NSAppearance(named: .aqua)
        Task { @MainActor in
            let monitor = DeviceMonitor(providers: [SampleProvider()])
            await monitor.refresh()
            let device = monitor.devices.first { $0.id == "demo-wireless" }!
            let view = DeviceDetailContent(device: device)
                .frame(width: 880)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.locale, L10n.locale)
                .preferredColorScheme(.light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Cannot render device detail")
            }
            try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            let scene = MenuBarScene(device: device)
                .environmentObject(monitor)
                .environmentObject(AppNavigation())
                .environmentObject(UpdateManager())
                .environment(\.locale, L10n.locale)
            let barRenderer = ImageRenderer(content: scene)
            barRenderer.scale = 2
            guard let barImage = barRenderer.nsImage,
                  let barTIFF = barImage.tiffRepresentation,
                  let barBitmap = NSBitmapImageRep(data: barTIFF),
                  let barPNG = barBitmap.representation(using: .png, properties: [:]) else {
                fatalError("Cannot render menu bar")
            }
            let barURL = URL(fileURLWithPath: CommandLine.arguments[2])
                .deletingLastPathComponent()
                .appendingPathComponent(L10n.language == .simplifiedChinese ? "menubar-zh-CN.png" : "menubar-en.png")
            try! barPNG.write(to: barURL)
            app.terminate(nil)
        }
        app.run()
    }
}
'''
with tempfile.TemporaryDirectory(prefix='mousemeter-readme-') as directory:
    package = Path(directory)
    shutil.copy2(root / 'Package.swift', package)
    shutil.copytree(root / 'Sources', package / 'Sources')
    shutil.copytree(root / 'Tests', package / 'Tests')
    label = package / 'Sources/MouseMeter/UI/MenuBarLabel.swift'
    label.write_text(label.read_text().replace('private struct MenuBarLabelContent', 'struct MenuBarLabelContent'))
    monitor_source = package / 'Sources/MouseMeter/Core/DeviceMonitor.swift'
    monitor_source.write_text(monitor_source.read_text().replace('lastRefresh = .now', 'lastRefresh = Date(timeIntervalSince1970: 1_767_268_800)'))
    panel_source = package / 'Sources/MouseMeter/UI/MenuBarPanel.swift'
    # AppKit-backed borderless buttons cannot be exported by SwiftUI ImageRenderer.
    panel_source.write_text(panel_source.read_text().replace('.buttonStyle(.borderless)', '.buttonStyle(.plain)'))
    # Preserve helpers referenced by the UI, replacing only the normal app lifecycle.
    entry = package / 'Sources/MouseMeter/App/MouseMeterApp.swift'
    helpers = entry.read_text().split('enum PermissionHelper {', 1)[1]
    entry.write_text(renderer + '\nenum PermissionHelper {' + helpers)
    subprocess.run(['swift', 'build', '--package-path', directory], check=True)
    binary = subprocess.check_output(['swift', 'build', '--package-path', directory, '--show-bin-path'], text=True).strip()
    for language, filename in [('en', 'overview-en.png'), ('zh-Hans', 'overview-zh-CN.png')]:
        subprocess.run([str(Path(binary) / 'MouseMeter'), language, str(output / filename), '-appLanguage', language], check=True)
