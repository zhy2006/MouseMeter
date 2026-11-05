# MouseMeter

A macOS menu bar app built with Swift and SwiftUI for monitoring mouse battery levels and DPI. Supports compatible Logitech HID++ mice and Bluetooth mice that expose battery information, with English, Simplified Chinese, and Japanese interfaces.

[简体中文](docs/README.zh-CN.md)

![MouseMeter in English](docs/images/overview-en.png)

*The image uses synthetic demo data.*

## Build and package

Requires macOS 15 or later and Xcode 16 or later with Swift 6. Run from the project root:

```bash
make dmg      # Build the app and DMG (default target)
make app      # Build build/MouseMeter.app only
make install  # Build and install to /Applications
make clean    # Remove packaging output
```

Builds support both Apple silicon and Intel Macs by default. The version is read from `VERSION`, and the DMG is saved to `build/MouseMeter-<version>.dmg`. Open the DMG and drag MouseMeter into Applications to install it.

## Code signing

The app and DMG currently use the self-signed certificate `Flick Self-Signed Code Signing` and are not notarized by Apple. macOS may block the app on first launch.

The default build requires this certificate and its private key in your local keychain. To build with your own signing identity:

```bash
make dmg SIGN_IDENTITY="Your Code Signing Identity"
```

For a local ad hoc signed build:

```bash
make dmg SIGN_IDENTITY=-
```

## License

[MIT](LICENSE) © 2026 zhy2006.
