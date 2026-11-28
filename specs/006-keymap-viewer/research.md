# Research: 006-keymap-viewer

**Date**: 2026-11-26 | **Phase**: 0 — Pre-plan research

## Codebase Inventory

### macOS app 结构

```
app/macos/Sources/
├── BleWidget/            # UI 层（AppKit，直接面向用户）
│   ├── AppDelegate.swift
│   ├── FloatingPanel.swift
│   └── main.swift
└── BleWidgetCore/        # 业务逻辑层（平台无关）
    ├── AppSettings.swift
    ├── BatteryStatus.swift
    ├── BLEClient.swift
    ├── CapabilityMatrix.swift
    ├── CompatibleKeyboard.swift
    ├── ConnectivityStatus.swift
    ├── DiagnosticsLogger.swift
    ├── HostStatusVisual.swift
    ├── KBPCompatibility.swift
    ├── KeyboardStatus.swift
    ├── LinkSlot.swift
    ├── LinkSlotCache.swift
    ├── LocalHostStatus.swift
    ├── Localization.swift
    └── StalenessTracker.swift
```

### 现有模式（供 006 遵循）

- **BleWidgetCore 分层**：纯逻辑放 BleWidgetCore，AppKit UI 放 BleWidget；新增 `KeymapModel.swift`（Core）+ `KeymapPanel.swift`（Widget）
- **AppDelegate 委托模式**：`BLEClientDelegate` 协议回调 → AppDelegate 转发给 Panel；006 新增 `didReceiveKeymapMeta` / `didReceiveKeymapData` 回调
- **NSPanel 模式**：`FloatingPanel` 是 `NSPanel` subclass，`init()` 构建 layout，`update(...)` 方法接收数据；`KeymapPanel` 遵循相同模式
- **AppSettings**：`UserDefaults` 包装，属性计算式访问；新增 `keymapHotkeyModifiers`、`keymapHotkeyKeyCode`、`keymapCacheByUUID` 存储键
- **KBP 版本检测**：`KBPCompatibility.swift` + `BLEClient didDetermineKBPMinor`；006 需要扩展为 `.onePointThree` 枚举值
- **L10n**：`Localization.swift` 提供 `L10n.text(key)` / `L10n.format(key, ...)`；新 key 遵循此模式
- **Constitution Principle III**：能力必须来自特征存在性（UUID），不得做键盘型号判断
- **Constitution Principle IV**：无数据时显示诚实空白，不猜测

### 现有协议

- `protocol/VERSION` = `1.2.0`
- 现有特征 UUID：`AA440AA1`（KBP 1.0）、`AA440AA2`（KBP 1.1）、`AA440AA3`（KBP 1.1）、`AA440AA4`（KBP 1.2）
- 006 新增：`AA440AA5`（KeymapMeta）、`AA440AA6`（KeymapData）

### BLE 读取模式

现有 `BLEClient.swift` 使用 CoreBluetooth：
- NOTIFY 特征：订阅 CCC，`centralManager(_:didUpdateValueFor:)`
- READ 特征（AA4）：`peripheral.readValue(for:)` 触发一次
- **KeymapData 分块**：标准 ATT `READ_BLOB`（`readValue(for:offset:)`），CoreBluetooth 通过 `CBPeripheral.maximumWriteValueLength` 控制 MTU；006 需要实现 offset 累加循环读取

### 渲染技术选型

- 现有 `FloatingPanel` 完全使用 `NSView` + AutoLayout + `CALayer`；没有引入 SwiftUI 或 Metal
- `KeymapView` 使用 `NSView.draw(_ rect:)` + CoreGraphics：
  - `CGContext.addRoundedRect` 画按键轮廓
  - `CGContext.saveGState` / `restoreGState` + `CGContext.rotate` 处理旋转键
  - `NSAttributedString` 绘制双行标签

### 全局热键

- 现有代码无全局热键；需引入 `Carbon.framework`（`RegisterEventHotKey` / `RemoveEventHandler`）
- macOS 12+ 推荐替代是 `NSEvent.addGlobalMonitorForEvents`，但不能拦截 keyDown（only monitor），Carbon API 仍是 app 级全局热键的标准方案

### 缓存方案

- `AppSettings` 包装 `UserDefaults`；`keymapCache` 以 `"keymapCache_\(uuid)_\(crc32hex)"` 为 key，存 `Data`（Codable JSON）

## 关键风险 & 决策

| 风险 | 决策 |
|------|------|
| ATT READ_BLOB 循环读取复杂性 | 在 BleWidgetCore 实现 `KeymapDataFetcher`，封装 offset 累加逻辑，减少 AppDelegate 侧复杂度 |
| Carbon.framework 全局热键 API 较老 | 使用 `RegisterEventHotKey`，封装为 `HotkeyRegistrar.swift`，隔离 Carbon 依赖 |
| KeymapPanel resize 时重绘性能 | `KeymapView` 重写 `draw(_:)`，不缓存 frame-level bitmap；仅在数据变化时 `setNeedsDisplay` |
| 首次连接引导弹窗时机 | AppDelegate 在 `didDetermineKBPMinor(.onePointThree)` 且 `AppSettings.keymapHotkeyKeyCode == 0` 时一次性弹窗 |
| CRC 碰撞逃生门 | 菜单项「强制刷新键位图」调用 `BLEClient.fetchKeymapData(ignoreCache: true)` |

## Constitution Checklist（Phase 0）

- [x] **I. Wire-Contract Self-Containment**：UUID 和 payload 格式将写入 `specs/006-keymap-viewer/contracts/`，待 ratify 后复制进 `protocol/`
- [x] **II. Backward Compatibility**：`KeymapMeta` / `KeymapData` 是可选新特征，老 app 忽略，`KBPMinor` 检测保证老键盘灰显
- [x] **III. Identity From Protocol**：能力判断来自特征 UUID 存在性，无型号白名单
- [x] **IV. Observable Degradation**：无 KBP 1.3 时灰显，断连时保留最后渲染并标注 stale
- [x] **V. Spec-First**：本 spec → plan → tasks 流程，contracts 先于实现
- [x] **VI. Bilingual**：内部 specs/ 文件豁免；`protocol/` 更新需双语
