# Tasks: 006-keymap-viewer

**Input**: Design documents from `/specs/006-keymap-viewer/`

**Prerequisites**: spec.md ✅, plan.md ✅, research.md ✅, data-model.md ✅, contracts/ble-keymap.md ✅

## Phase 1: Foundation（阻塞所有后续工作）

**Purpose**: 数据模型、BLE 读取、缓存——所有 US 均依赖这三个文件

- [ ] T001 在 `BleWidgetCore/KeymapModel.swift` 中定义 `BehaviorID`、`KeyEntry`、`BindingEntry`、`KeymapSnapshot`、`KeymapMeta` 类型（Codable，参照 data-model.md）
- [ ] T002 [P] 为 `KeymapModel` 中所有公共解析方法添加 XCTest（`BleWidgetCoreTests/KeymapModelTests.swift`）
- [ ] T003 [P] 在 `BleWidgetCore/KeymapModel.swift` 中实现 `BindingEntry.displayLabel(layerNames:)` —— 按 data-model.md 三层渲染表映射所有 `BehaviorID`
- [ ] T004 在 `BleWidgetCore/KeymapDataFetcher.swift` 中实现 `KeymapDataFetcher`：ATT READ_BLOB 循环（offset 累加）、完整 payload 拼合、解析为 `KeymapSnapshot`
- [ ] T005 [P] 为 `KeymapDataFetcher` 解析逻辑添加纯函数 XCTest（mock Data，不依赖 BLE 硬件）
- [ ] T006 在 `BleWidgetCore/AppSettings.swift` 中新增：`keymapHotkeyModifiers: UInt32`、`keymapHotkeyKeyCode: UInt32`、`keymapSnapshot(for:crc32:) -> KeymapSnapshot?`、`setKeymapSnapshot(_:for:crc32:)`
- [ ] T007 在 `BleWidgetCore/KBPCompatibility.swift` 中扩展 `KBPMinor` 枚举，新增 `.onePointThree` case；更新 `BLEClient` 的 KBP 版本检测逻辑以识别 `AA440AA5`

**Checkpoint**: Foundation 完成后 US1~US3 可并行推进

---

## Phase 2: US1 — 快速唤醒键位图（P1）🎯 MVP

**Goal**: 全局快捷键/菜单项 → KeymapPanel 在 2s 内出现，显示 layer 0 全量键位图

**Independent Test**: quickstart.md 场景 1

- [ ] T010 在 `BleWidget/KeymapView.swift` 中实现 `KeymapView: NSView`：`draw(_:)` 用 CoreGraphics 画圆角矩形 + 双行标签；单位转换 1u=54pt；支持旋转键（`CGContext.saveGState` + `rotate`）
- [ ] T011 在 `BleWidget/KeymapPanel.swift` 中实现 `KeymapPanel: NSPanel`：`NSSegmentedControl` layer 选择器（顶部）+ `KeymapView`（主体）；`NSPanel` resizable；`init()` 构建 layout，`update(snapshot:)` 刷新数据
- [ ] T012 在 `BleWidget/HotkeyRegistrar.swift` 中封装 Carbon `RegisterEventHotKey` / `RemoveEventHandler`，提供 `register(modifiers:keyCode:handler:)` 和 `unregister()`
- [ ] T013 在 `AppDelegate.swift` 中：新增 `keymapPanel: KeymapPanel`；菜单栏新增「键位图」和「强制刷新键位图」菜单项；在 `bleClient(_:didDetermineKBPMinor:)` 分支中处理 `.onePointThree`，调用 `KeymapDataFetcher` 拉取数据；连线 `HotkeyRegistrar` 实现 toggle 行为
- [ ] T014 实现首次连接 KBP 1.3 时的引导弹窗（`NSAlert` 或简单 sheet），引导用户设置全局快捷键；`AppSettings.keymapHotkeyKeyCode == 0` 时触发一次

**Checkpoint**: US1 完成后可验证 quickstart.md 场景 1、8

---

## Phase 3: US2 — Layer 切换与实时跟随（P1）

**Goal**: segmented control 手动切换 layer；KBP 1.0 notify 自动高亮但不强制切换

**Independent Test**: quickstart.md 场景 4

- [ ] T020 在 `KeymapPanel` 中实现 `NSSegmentedControl` 点击响应：更新 `KeymapView` 渲染指定 layer 的 bindings
- [ ] T021 在 `BLEClient` / `AppDelegate` 中监听 KBP 1.0 layer-index notify，调用 `KeymapPanel.highlightLayer(_:)` 高亮对应 segment（不改变当前渲染 layer）

**Checkpoint**: US2 完成后可验证 quickstart.md 场景 4

---

## Phase 4: US3 — 零维护自适应布局（P2）

**Goal**: 切换键盘时自动更新布局；老固件灰显；断连时 stale 状态

**Independent Test**: quickstart.md 场景 5、9

- [ ] T030 在 `AppDelegate.bleClient(_:didChangeActiveKeyboard:)` 中：清除旧键盘缓存引用，触发新键盘的 `KeymapMeta` 读取
- [ ] T031 在 `AppDelegate.bleClient(_:didDetermineKBPMinor:)` 中：非 `.onePointThree` 时灰显「键位图」菜单项，`KeymapPanel` 显示「固件不支持键位图」提示
- [ ] T032 在 `AppDelegate.bleClient(_:didChangeState:)` 中：断连时调用 `KeymapPanel.markDisconnected()`，面板显示 disconnected 覆盖层，不清空最后渲染内容

**Checkpoint**: US3 完成后可验证 quickstart.md 场景 5、9

---

## Phase 5: 缓存与强制刷新（跨 US，FR-002/FR-003/FR-012）

- [ ] T040 在 `AppDelegate` 或 `KeymapDataFetcher` 中实现 CRC 比对逻辑：连接时读 `KeymapMeta`，与 `AppSettings` 缓存比对；一致则跳过 `KeymapData` READ
- [ ] T041 实现「强制刷新键位图」菜单项：调用 `fetchKeymapData(ignoreCache: true)`，拉取完成后刷新 `KeymapPanel`

---

## Phase 6: Protocol 文档更新

- [ ] T050 更新 `protocol/README.md`（双语 EN/中文）：新增 KBP 1.3 §，描述 `AA440AA5`/`AA440AA6` UUID、payload 格式，来自 `contracts/ble-keymap.md`
- [ ] T051 更新 `protocol/CHANGELOG.md`（双语）：新增 1.3.0 条目

---

## Dependencies & Execution Order

```
Phase 1（T001~T007）→ Phase 2（T010~T014）→ Phase 3（T020~T021）→ Phase 4（T030~T032）
                                           ↘
                                            Phase 5（T040~T041，可与 Phase 3/4 并行）
Phase 6（T050~T051，可与任意阶段并行）
```

- T002、T003、T005 与 T001/T004 分别可并行（不同文件）
- Phase 3、4、5 均依赖 Phase 2 完成
- Phase 6 仅依赖 contracts/ble-keymap.md（已完成），可随时推进
