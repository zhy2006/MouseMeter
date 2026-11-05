# MouseMeter

macOS 菜单栏鼠标电量 / DPI 查看工具。

- **菜单栏**：电池图标 + 剩余电量百分比（可选显示 DPI），点击弹出所有鼠标的概览
- **主界面**：电量环形仪表、当前 DPI 及其在传感器范围内的位置、设备信息；支持深色模式
- 低电量通知、离线设备保留上次读数、登录时启动、可调刷新间隔

## 支持的设备

| 数据源 | 设备 | 电量 | DPI |
| --- | --- | --- | --- |
| `LogitechHIDPPProvider` | 罗技 HID++ 2.0 设备：Lightspeed / Unifying / Bolt 接收器、有线、蓝牙直连 | ✅ (0x1004 / 0x1000 / 0x1001) | ✅ (0x2202 / 0x2201) |
| `BluetoothBatteryProvider` | 妙控鼠标及通过系统蓝牙电量服务上报电量的鼠标 | ✅ | ❌ |

## 构建与运行

需要 macOS 15+、Xcode 16+（Swift 6 工具链）。

```bash
Scripts/build-app.sh            # 生成 build/MouseMeter.app（通用二进制，ad-hoc 签名）
Scripts/build-app.sh --install  # 同时安装到 /Applications

swift run MouseMeter            # 开发时直接运行（无 bundle，通知与登录项不可用）
swift run MouseMeter --dump     # 读取一次并在终端打印所有设备，调试协议用
```

部分接收器的接口包含键盘用途，macOS 会要求 **输入监控** 权限；未授权且读不到任何设备时，界面会给出提示和跳转按钮。

## 架构

```
Sources/MouseMeter
├── App/            入口、AppDelegate
├── Core/
│   ├── MouseDevice.swift          统一的设备模型（电量、DPI、连接方式…）
│   ├── MouseDeviceProvider.swift  数据源协议 + ProviderRegistry
│   ├── DeviceMonitor.swift        定时刷新、跨数据源去重、离线保留、低电量提醒
│   └── AppSettings.swift
├── Providers/
│   ├── HIDPP/      罗技 HID++：Channel（IOKit 收发）→ Device（feature 解析）→ Provider
│   └── Bluetooth/  IORegistry BatteryPercent
└── UI/             菜单栏图标、弹出面板、主窗口、设置
```

UI 只依赖 `MouseDevice`，不感知具体协议。

## 添加新的鼠标协议

1. 在 `Providers/` 下新建一个类型，实现 `MouseDeviceProvider`：

   ```swift
   @MainActor
   final class RazerProvider: MouseDeviceProvider {
       let id = "razer"
       let displayName = "Razer"
       let priority = 90                    // 高于通用蓝牙数据源(10)，同名设备以它为准
       var onDevicesChanged: (() -> Void)?  // 设备插拔时调用，触发立即刷新

       func start() { /* 注册 IOHIDManager 回调等 */ }
       func stop() {}

       func fetchDevices() async throws -> [MouseDevice] {
           // 与设备通信，返回 MouseDevice 数组；读不到的字段（battery / dpi）留 nil 即可
       }
   }
   ```

2. 在 `ProviderRegistry.makeDefault()` 里加上 `RazerProvider()`。

3. `swift run MouseMeter --dump` 验证输出。

约定：

- `MouseDevice.id` 需在多次刷新间稳定，用于保留离线设备和记住菜单栏选中项。
- 多个数据源识别到同一只鼠标时（按名称归一化后的 `dedupeKey` 判断），保留 `priority` 更高者。
- 需要用户授权时抛出 `ProviderError.inputMonitoringRequired`，界面会显示引导。
