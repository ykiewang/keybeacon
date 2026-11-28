# Implementation Plan: 006-keymap-viewer

**Branch**: `feat/006-keymap-viewer` | **Date**: 2026-11-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-keymap-viewer/spec.md`

## Summary

在 macOS app 新增键位图速查功能（KBP 1.3）：连接时读取 `KeymapMeta`（CRC32 + 元信息）做缓存校验，CRC 变化时拉取 `KeymapData`（物理布局 + keycode 表），用 `NSPanel` + CoreGraphics 渲染按键形状与标签，支持全局热键唤醒/隐藏。

## Technical Context

**Language/Version**: Swift 5.9, macOS 12+

**Primary Dependencies**: AppKit, CoreBluetooth（已存在）, CoreGraphics（已存在）, Carbon.framework（新增，全局热键）

**Storage**: UserDefaults via AppSettings（已存在，新增 keymap cache key）

**Testing**: XCTest（已存在，须为所有新 BleWidgetCore 公共类型添加单元测试）

**Target Platform**: macOS 12+

**Project Type**: macOS desktop app（menu bar accessory）

**Performance Goals**: 有缓存时 P95 ≤ 300ms，无缓存时 P95 ≤ 2s

**Constraints**: 向后兼容 KBP 1.0/1.1/1.2，老固件不崩溃，零额外 BLE traffic（CRC 一致时）

**Scale/Scope**: 单 macOS target，新增 ~6 个源文件（Core 3 + Widget 3）

## Constitution Check

| 原则 | 评估 |
|------|------|
| I. Wire-Contract Self-Containment | UUID 和 payload 格式在 `contracts/ble-keymap.md` 中先于实现定义；ratify 后复制进 `protocol/` |
| II. Backward Compatibility | `KeymapMeta`/`KeymapData` 是可选新特征；`KBPMinor.onePointThree` 枚举值；老 app 枚举到未知 UUID 时忽略 |
| III. Identity From Protocol | 能力判断来自 `AA440AA5` UUID 存在性；无型号白名单 |
| IV. Observable Degradation | 无 KBP 1.3 时灰显菜单项；断连时保留最后渲染并标注 disconnected；数据拉取中显示 loading placeholder |
| V. Spec-First | 本 spec → plan → tasks → analyze → impl；contracts 先于任何实现代码 |
| VI. Bilingual | specs/ 内部文件豁免；`protocol/` 更新需双语 |

**GATE 通过**，可进入 Phase 1。

## Project Structure

### Documentation (this feature)

```text
specs/006-keymap-viewer/
├── spec.md
├── research.md
├── plan.md              ← 本文件
├── data-model.md        ← Phase 1 output
├── quickstart.md        ← Phase 1 output
├── contracts/
│   └── ble-keymap.md    ← Phase 1 output（UUID、payload 格式）
└── tasks.md             ← Phase 2 output (/speckit-tasks)
```

### Source Code

```text
app/macos/Sources/
├── BleWidgetCore/                    ← 业务逻辑，平台无关
│   ├── KeymapModel.swift             ← NEW: KeyEntry, BindingEntry, KeymapSnapshot, BehaviorID
│   ├── KeymapDataFetcher.swift       ← NEW: ATT READ_BLOB 循环读取 + CRC 校验 + 缓存
│   └── AppSettings.swift             ← MODIFY: 新增 hotkey / cache keys
└── BleWidget/                        ← AppKit UI
    ├── KeymapPanel.swift             ← NEW: NSPanel subclass，layer 选择器 + KeymapView
    ├── KeymapView.swift              ← NEW: NSView + CoreGraphics 渲染
    ├── HotkeyRegistrar.swift         ← NEW: Carbon RegisterEventHotKey 封装
    └── AppDelegate.swift             ← MODIFY: KBPMinor.onePointThree + keymap menu items
```

## Implementation Phases

### Phase 0（已完成）: Research
见 `research.md`。

### Phase 1: Design（本阶段）

1. **contracts/ble-keymap.md** — 定义 `AA440AA5`/`AA440AA6` 的 UUID、payload byte layout、ATT READ_BLOB 分块协议
2. **data-model.md** — `KeyEntry`、`BindingEntry`、`BehaviorID` 枚举、`KeymapSnapshot`、`KeymapCache` 存储格式
3. **quickstart.md** — Given/When/Then 场景映射 FR/SC

### Phase 2: Tasks

由 `/speckit-tasks` 生成 `tasks.md`，分解为原子任务。

### Phase 3: Analyze

`/speckit-analyze` 验证 CRITICAL=0, HIGH=0。

### Phase 4: Implement（执行顺序）

1. `KeymapModel.swift`（BleWidgetCore）— 数据模型和解析逻辑，含 XCTest
2. `KeymapDataFetcher.swift`（BleWidgetCore）— BLE 读取、缓存、CRC 校验，含 XCTest
3. `AppSettings.swift` 扩展 — hotkey key codes、keymap cache
4. `KBPMinor` 枚举扩展 + `BLEClient` 新回调
5. `KeymapView.swift` — CoreGraphics 渲染
6. `KeymapPanel.swift` — NSPanel + layer 选择器
7. `HotkeyRegistrar.swift` — Carbon 热键封装
8. `AppDelegate.swift` — 菜单项 + 委托连线 + 首次连接引导弹窗
9. `protocol/README.md` / `CHANGELOG.md` — 双语更新 KBP 1.3 条目

## Complexity Tracking

> 无 Constitution 违规，表格留空。
