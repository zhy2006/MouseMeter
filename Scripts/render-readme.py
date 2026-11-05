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
    # Preserve helpers referenced by the UI, replacing only the normal app lifecycle.
    entry = package / 'Sources/MouseMeter/App/MouseMeterApp.swift'
    helpers = entry.read_text().split('enum PermissionHelper {', 1)[1]
    entry.write_text(renderer + '\nenum PermissionHelper {' + helpers)
    subprocess.run(['swift', 'build', '--package-path', directory], check=True)
    binary = subprocess.check_output(['swift', 'build', '--package-path', directory, '--show-bin-path'], text=True).strip()
    for language, filename in [('en', 'overview-en.png'), ('zh-Hans', 'overview-zh-CN.png')]:
        subprocess.run([str(Path(binary) / 'MouseMeter'), language, str(output / filename), '-appLanguage', language], check=True)
