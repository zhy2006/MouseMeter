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

Available readings depend on the features exposed by each device and connection. Protocol support does not guarantee compatibility with every model. MouseMeter displays DPI; it does not change it. The interface supports Simplified Chinese, English, and Japanese. It follows the system language by default; select a language in Settings to apply it immediately. Unsupported system languages fall back to English.

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

The packaging scripts build a universal binary for Apple silicon and Intel Macs. The version comes from the root `VERSION` file and is written into the packaged app metadata. Open the DMG and drag MouseMeter into Applications to install it.

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

## GitHub Releases

The `Release macOS` workflow runs when a version tag such as `v1.0.0` is pushed. Commit the matching `VERSION` file (`1.0.0`) first, then create and push the tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow verifies that the tag matches `VERSION` before building. Release `v1.0.0` includes:

- `MouseMeter-1.0.0-x64.dmg` for Intel Macs.
- `MouseMeter-1.0.0-arm64.dmg` for Apple silicon Macs.

CI signs both the app and DMG with `Flick Self-Signed Code Signing` and does not notarize the app. Configure these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded `.p12` export of the Flick certificate **including its private key** |
| `MACOS_CERTIFICATE_PASSWORD` | Password used to protect the exported `.p12` |

Export the identity from Keychain Access, then copy its encoded contents using `base64 < Flick.p12 | pbcopy`. The workflow creates a random password for its temporary keychain and cleans up the keychain and certificate files even if the build fails.

 The workflow uses the repository's built-in `GITHUB_TOKEN`; repository policy must allow it to write releases and delete Actions artifacts. Temporary build artifacts are deleted after successful publication, with a 1-day retention period as a fallback if publication fails. No build cache is uploaded. Deleting artifacts reduces storage usage, not consumed build minutes.

For a local single-architecture package, use `ARCH=x86_64 make dmg` or `ARCH=arm64 make dmg` (with your signing identity as needed). Without `ARCH`, local builds remain universal.

## In-app updates

MouseMeter checks `zhy2006/MouseMeter` GitHub Releases on startup when the last successful check is at least 6 hours old, then checks periodically while running. Only stable releases newer than the installed version are offered. A menu bar panel link opens the update settings; you can also check manually or disable automatic checks there.

Choose **Download Update and Restart** to download the matching x64 or arm64 DMG, verify its size and GitHub SHA-256 digest when available, and validate the app version, macOS compatibility, and code signature against the current app's signing certificate. The updater stages the replacement before quitting, replaces the app, and relaunches it. A failed replacement restores the previous app when possible. Your settings remain in UserDefaults.

Updates require a packaged `.app` in a writable location, such as `/Applications` or `~/Applications`; updating from a mounted DMG or `swift run` is unsupported. Keep using the same Flick certificate and private key for future releases. Changing the signing identity or using an ad hoc build requires a manual installation from the Releases page.

## Permissions

Some receiver interfaces include keyboard usages and require **Input Monitoring** permission. If device detection is blocked, enable MouseMeter in **System Settings → Privacy & Security → Input Monitoring**. The app provides a shortcut when it detects a permission issue.

Allow notifications to receive low battery alerts. Launch at login can be enabled in the app settings when running the packaged app.

## Project structure

```text
Sources/MouseMeter/
├── App/          App entry point and lifecycle
├── Core/         Device model, provider registry, monitoring, and settings
├── Updates/      GitHub release checks, validation, and installation
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
