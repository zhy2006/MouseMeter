# MouseMeter

A macOS menu bar app for monitoring mouse battery levels and DPI, built with Swift and SwiftUI.

[简体中文](docs/README.zh-CN.md)

## Features

- Menu bar battery icon and optional battery percentage and DPI display.
- A quick overview of connected mice, with a selectable device for the menu bar.
- A main window with battery gauges, current DPI, sensor range, and device details, with dark mode support.
- Configurable low battery notifications (20% by default).
- Automatic refresh every 15 seconds to 5 minutes (1 minute by default), and last known readings for offline devices.
- Launch at login.

## Device support

| Data source | Devices | Battery | DPI |
| --- | --- | --- | --- |
| Logitech HID++ 2.0 | Compatible Logitech mice over Lightspeed, Unifying, or Bolt receivers, USB, or direct Bluetooth | Yes, via `0x1004`, `0x1000`, or `0x1001` | Yes, via `0x2202` or `0x2201` |
| System Bluetooth battery data | Magic Mouse and other mice exposing battery information through macOS IORegistry | Yes | No |

Available readings depend on the features exposed by each device and connection. Protocol support does not guarantee compatibility with every model. MouseMeter displays DPI; it does not change it. The current app interface is in Simplified Chinese.

## Requirements

- macOS 15 or later.
- Xcode 16 or later with a Swift 6 toolchain for building from source.
- A code signing identity available in your local keychain when using the packaging scripts.

## Build and install

Run these commands from the project root:

```bash
make dmg      # Default target; creates build/MouseMeter-1.0.0.dmg
make app      # Creates build/MouseMeter.app
make install  # Builds and copies the app to /Applications
make clean    # Removes build/ packaging output
```

The packaging scripts build a universal binary for Apple silicon and Intel Macs. The version comes from `Resources/Info.plist`. Open the DMG and drag MouseMeter into Applications to install it.

By default, both the app and DMG are signed with `Flick Self-Signed Code Signing`. This certificate is specific to the original development environment; builds fail if the signing identity and its private key are unavailable. Specify your own identity with:

```bash
make dmg SIGN_IDENTITY="Your Code Signing Identity"
```

For a local ad hoc signed build, you can use `make app SIGN_IDENTITY=-`. The scripts do not perform Apple notarization.

For development or protocol debugging:

```bash
swift run MouseMeter
swift run MouseMeter --dump  # Prints device readings once, then exits
```

Running through `swift run` does not create an app bundle; notifications and launch at login are unavailable in this mode.

## Permissions

Some receiver interfaces include keyboard usages and require **Input Monitoring** permission. If device detection is blocked, enable MouseMeter in **System Settings → Privacy & Security → Input Monitoring**. The app provides a shortcut when it detects a permission issue.

Allow notifications to receive low battery alerts. Launch at login can be enabled in the app settings when running the packaged app.

## Project structure

```text
Sources/MouseMeter/
├── App/          App entry point and lifecycle
├── Core/         Device model, provider registry, monitoring, and settings
├── Providers/
│   ├── HIDPP/    Logitech HID++ transport and feature parsing
│   └── Bluetooth/ System Bluetooth battery readings
└── UI/           Menu bar, overview window, settings, and components
Resources/        App metadata and icon source
Scripts/          Icon generation, app packaging, and DMG creation
```

The UI consumes the shared `MouseDevice` model. `DeviceMonitor` refreshes providers, deduplicates devices, retains offline readings, and sends low battery notifications.

## Adding a device provider

1. Add a type under `Sources/MouseMeter/Providers/` conforming to the `@MainActor` protocol `MouseDeviceProvider`.
2. Implement its identity, display name, priority, lifecycle methods, and `fetchDevices()`. Call `onDevicesChanged` when devices connect or disconnect to request a refresh.
3. Register the provider in `ProviderRegistry.makeDefault()` in `Core/MouseDeviceProvider.swift`.
4. Check its readings with `swift run MouseMeter --dump`.

Keep `MouseDevice.id` stable between refreshes and leave unavailable battery or DPI values as `nil`. Devices with the same normalized name (`dedupeKey`) are deduplicated in favor of the provider with the higher priority. Throw `ProviderError.inputMonitoringRequired` when Input Monitoring permission is needed.

## License

[MIT](LICENSE) © 2026 zhy2006.
