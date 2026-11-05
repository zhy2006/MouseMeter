# MouseMeter

使用 Swift 和 SwiftUI 构建的 macOS 菜单栏工具，用于查看鼠标电量和 DPI。

[English](../README.md)

## 功能

- 菜单栏电池图标，可选显示电量百分比和当前 DPI。
- 点击菜单栏即可查看鼠标概览，并选择菜单栏展示的设备。
- 主窗口显示电量仪表、当前 DPI、传感器范围和设备详情，支持深色模式。
- 可配置低电量通知，默认阈值为 20%。
- 自动刷新间隔可选 15 秒至 5 分钟，默认为 1 分钟；离线设备保留上次读数。
- 支持登录时启动。

## 设备支持

| 数据源 | 设备 | 电量 | DPI |
| --- | --- | --- | --- |
| Logitech HID++ 2.0 | 通过 Lightspeed、Unifying、Bolt 接收器、USB 或蓝牙直连的兼容罗技鼠标 | 支持，通过 `0x1004`、`0x1000` 或 `0x1001` | 支持，通过 `0x2202` 或 `0x2201` |
| 系统蓝牙电量数据 | 妙控鼠标及通过 macOS IORegistry 提供电量信息的鼠标 | 支持 | 不支持 |

实际可读取的数据取决于设备和连接方式暴露的功能，协议支持不代表所有型号均已兼容。MouseMeter 仅显示 DPI，不修改 DPI。目前应用界面为简体中文。

## 环境要求

- macOS 15 或更高版本。
- 从源码构建需要 Xcode 16 或更高版本，以及 Swift 6 工具链。
- 使用打包脚本时，本机钥匙串中需有可用的代码签名身份。

## 构建与安装

在项目根目录执行：

```bash
make dmg      # 默认目标，生成 build/MouseMeter-1.0.0.dmg
make app      # 生成 build/MouseMeter.app
make install  # 构建并复制到 /Applications
make clean    # 清理 build/ 下的打包产物
```

打包脚本生成适用于 Apple 芯片和 Intel Mac 的通用二进制。版本号取自 `Resources/Info.plist`。打开 DMG 后，将 MouseMeter 拖入 Applications 即可安装。

App 和 DMG 默认使用 `Flick Self-Signed Code Signing` 签名。该证书属于原开发环境；本机缺少对应签名身份或私钥时，构建会失败。可以指定自己的签名身份：

```bash
make dmg SIGN_IDENTITY="你的代码签名身份"
```

本地使用也可执行 `make app SIGN_IDENTITY=-` 生成临时签名（ad hoc）的应用。脚本不执行 Apple 公证。

开发运行或调试协议：

```bash
swift run MouseMeter
swift run MouseMeter --dump  # 读取并打印一次设备数据，然后退出
```

通过 `swift run` 运行不会创建 App bundle，此模式下通知和登录时启动不可用。

## 权限

部分接收器接口包含键盘用途，需要**输入监控**权限。如果设备检测受阻，请在**系统设置 → 隐私与安全性 → 输入监控**中允许 MouseMeter。应用检测到权限问题时会提供跳转入口。

接收低电量提醒需要允许通知。使用打包后的应用时，可以在应用设置中启用登录时启动。

## 项目结构

```text
Sources/MouseMeter/
├── App/          应用入口与生命周期
├── Core/         设备模型、数据源注册、监控与设置
├── Providers/
│   ├── HIDPP/    罗技 HID++ 通信与功能解析
│   └── Bluetooth/ 系统蓝牙电量读取
└── UI/           菜单栏、主窗口、设置与通用组件
Resources/        应用元数据与图标源文件
Scripts/          图标生成、App 打包与 DMG 制作
```

UI 使用统一的 `MouseDevice` 模型。`DeviceMonitor` 负责刷新数据源、设备去重、离线读数保留和低电量通知。

## 添加设备数据源

1. 在 `Sources/MouseMeter/Providers/` 下添加类型，实现标记为 `@MainActor` 的 `MouseDeviceProvider` 协议。
2. 实现标识、显示名称、优先级、生命周期方法和 `fetchDevices()`；设备连接或断开时调用 `onDevicesChanged`，请求刷新。
3. 在 `Core/MouseDeviceProvider.swift` 的 `ProviderRegistry.makeDefault()` 中注册数据源。
4. 使用 `swift run MouseMeter --dump` 检查读取结果。

`MouseDevice.id` 应在多次刷新之间保持稳定，无法读取的电量或 DPI 字段保留为 `nil`。名称归一化后具有相同 `dedupeKey` 的设备会按数据源优先级去重，优先保留数值较高者。需要输入监控权限时，抛出 `ProviderError.inputMonitoringRequired`。

## 许可证

本项目采用 [MIT 许可证](../LICENSE)，© 2026 zhy2006。
