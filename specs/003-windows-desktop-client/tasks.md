---

description: "Task list for Windows 桌面客户端（KeyBeacon Windows Client）"

---

# Tasks: Windows 桌面客户端（KeyBeacon Windows Client）

**Feature**: `specs/003-windows-desktop-client` | **Date**: 2026-10-24

**Input**: 设计文档来自 `specs/003-windows-desktop-client/`：plan.md、spec.md、research.md、data-model.md、contracts/、quickstart.md

**Tests**: 解析层测试为**必需**（SC-005 / FR-013 要求以共享测试向量验证 `KeyBeacon.Core`）；BLE/UI 层以 quickstart 手工剧本 + Phase 0 probe 真机验收，不额外生成自动化测试。

**Organization**: 按用户故事分组，每故事可独立实现与测试。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1..US6）
- 所有任务含精确文件路径

## Path Conventions

工程根：`app/windows/`（与 `app/macos/` 平级，见 plan.md 结构）。

- 纯逻辑：`app/windows/src/KeyBeacon.Core/`（`net8.0`，零平台依赖）
- 平台层：`app/windows/src/KeyBeacon.App/`（`net8.0-windows10.0.19041.0`）
- 测试：`app/windows/tests/KeyBeacon.Core.Tests/`（`net8.0`）
- Phase 0 CLI：`app/windows/tools/KeyBeacon.Probe/`（`net8.0-windows10.0.19041.0`）

> **环境约束**：本仓库主机为 macOS，Windows 代码可写但**不可编译/运行/BLE 测试**。标注 🖥️ 的任务 MUST 在真实 Windows 主机（Win10 2004+/11）+ 参考键盘（Corne）上执行。

---

## Phase 1: Setup（共享基础设施）

**Purpose**: 工程骨架与依赖初始化

- [X] T001 创建 `app/windows/KeyBeacon.sln` 与四个工程骨架：`src/KeyBeacon.Core`（`net8.0`）、`src/KeyBeacon.App`（`net8.0-windows10.0.19041.0`）、`tests/KeyBeacon.Core.Tests`（`net8.0`）、`tools/KeyBeacon.Probe`（`net8.0-windows10.0.19041.0`）
- [X] T002 [P] 创建 `app/windows/Directory.Build.props`（`Nullable=enable`、`LangVersion=12`、`TreatWarningsAsErrors=true`）与 `app/windows/.gitignore`（忽略 `bin/`、`obj/`）
- [X] T003 [P] 在 `app/windows/src/KeyBeacon.App/KeyBeacon.App.csproj` 添加依赖：`H.NotifyIcon.Wpf`、`Microsoft.Extensions.Logging`、`Serilog`、`Serilog.Sinks.File`
- [X] T004 [P] 在 `app/windows/tests/KeyBeacon.Core.Tests/KeyBeacon.Core.Tests.csproj` 添加 xUnit + `Microsoft.NET.Test.Sdk` + `xunit.runner.visualstudio`
- [X] T005 [P] 创建本地化骨架 `app/windows/src/KeyBeacon.App/Localization/Resources.resx`（英文默认）与 `Resources.zh-CN.resx`

---

## Phase 2: Foundational（阻塞所有用户故事）

**Purpose**: `KeyBeacon.Core` 纯解析器（data-model.md §1–§6）+ 日志/设置/本地化基础设施。**⚠️ 所有用户故事在 Phase 2 + Phase 3(probe) 完成前不得开始。**

- [X] T006 [P] 实现 `app/windows/src/KeyBeacon.Core/KbpUuids.cs`：AA0/AA1/AA2/AA3 常量、`IsKeyBeaconFamily`（后缀 `-F5ED-4C48-84A1-8062D20D3D55`）、`Classify(services)` → supported/unsupportedVersion/notAKeyboard
- [X] T007 [P] 实现 `app/windows/src/KeyBeacon.Core/KeyboardStatus.cs`：`Parse`（`Length<2`→null；byte0=index，byte1=mods，byte2.. UTF-8），空名回退 `L{index}`；修饰键合并 Shift=`&0x22`、Control=`&0x11`、Alt=`&0x44`、Gui=`&0x88`；`Disconnected` 哨兵
- [X] T008 [P] 实现 `app/windows/src/KeyBeacon.Core/CapabilityMatrix.cs`：bit0–7 解码、`RawByte` 无损往返、`IsConsistent`（IV-C1：HasSplitLink→IsSplit；IV-C3：HasRightCharging→IsSplit&&HasLeftCharging）
- [X] T009 [P] 实现 `app/windows/src/KeyBeacon.Core/ConnectivityStatus.cs`：`Parse`（`Length<7`→null，C-C1；取前 7，尾部计入 TrailingBytesIgnored，C-C2）；子结构 Link/Profile/SplitLinkFlags/OutputEndpoint/ChargingFlags（data-model §3 位域逐字对齐）
- [X] T010 [P] 实现 `app/windows/src/KeyBeacon.Core/BatteryStatus.cs`：`Parse(data,isSplit)`（非 split 必 1 字节 C-B1；split 必 2 字节 C-B2）；`BatteryReading` 解码（0..100→Percent、255→Unavailable 非越界、101..254→Unavailable 越界 C-B3）
- [X] T011 [P] 实现 `app/windows/src/KeyBeacon.Core/StalenessTracker.cs`：`StalenessWindow=3.0s`、`RecordNotify`（时间不回退）、`IsStale`（未记录/forced→true）、`ForceStaleAll`
- [X] T012 [P] 实现 `app/windows/src/KeyBeacon.Core/CompatibleKeyboard.cs`：`DisplayName`（空名→`Keyboard {id前8}`）、`ResolveSelection(candidates,remembered)`（remembered 命中→它；唯一→它；否则 null）
- [X] T013 [P] 测试 `app/windows/tests/KeyBeacon.Core.Tests/KeyboardStatusTests.cs` 与 `CapabilityMatrixTests.cs`：层/修饰键组合、空名回退、IV-C1/IV-C3 违背、RawByte 往返（对齐 `conformance/tests` 向量）
- [X] T014 [P] 测试 `app/windows/tests/KeyBeacon.Core.Tests/ConnectivityStatusTests.cs` 与 `BatteryStatusTests.cs`：7 字节位域矩阵、短/长 payload、overall/split × percent/255/越界
- [X] T015 [P] 测试 `app/windows/tests/KeyBeacon.Core.Tests/StalenessTrackerTests.cs` 与 `CompatibleKeyboardTests.cs` 与 `KbpUuidsTests.cs`：3s 边界、时间回退、选择解析、家族分类
- [X] T016 [P] 实现 `app/windows/src/KeyBeacon.App/Diagnostics/DiagnosticsLogger.cs`：类别 `capability/profile/battery/staleness/connection` 与事件/字段名逐字对齐 research.md §4（`Microsoft.Extensions.Logging` 抽象）
- [X] T017 [P] 配置滚动文件日志 `app/windows/src/KeyBeacon.App/Diagnostics/LoggingSetup.cs`：Serilog rolling file 落 `%LOCALAPPDATA%\KeyBeacon\logs\`，单文件≤10MB、保留≤7（FR-022）
- [X] T018 [P] 实现设置 `app/windows/src/KeyBeacon.App/Settings/AppSettings.cs`：`SelectedKeyboardId`、`DisplayMode`、`PinnedCorner`、`VerboseLogging`、`UICulture`，读写 `%LOCALAPPDATA%\KeyBeacon\settings.json`
- [X] T019 [P] 实现本地化辅助 `app/windows/src/KeyBeacon.App/Localization/LocalizationService.cs`：按 `CultureInfo.CurrentUICulture` 选 zh-*→中文、其余→英文（FR-021）

**Checkpoint**: 纯解析器可 `dotnet test` 全绿（无需 BLE 硬件）；基础设施就绪。

---

## Phase 3: Phase 0 可行性 Probe（实现门禁 / FR-014）

**Purpose**: 在真机验证 WinRT 可行性（research.md §2 P1–P6）。**任一阻塞项（P1–P5）FAIL ⇒ 按 research.md §3 回退，暂停后续用户故事。**

**Independent Test**: 在 Windows + Corne 上运行 `KeyBeacon.Probe`，退出码 0 且 `probe-run.json` 的 P1–P5 全 PASS（契约见 `contracts/probe-cli.md`）。

- [X] T020 实现 `app/windows/tools/KeyBeacon.Probe/Program.cs`：`[MTAThread]` 入口 + 参数解析 `--device/--timeout/--json/--verbose`（CLI-1）
- [X] T021 [P] 实现 `app/windows/tools/KeyBeacon.Probe/BleProbe.cs`：`GetDeviceSelectorFromConnectionStatus(Connected)` + `FindAllAsync` + `DeviceWatcher`；`FromIdAsync` → `GetGattServicesAsync` 带超时（C-2 陈旧连接策略）
- [X] T022 实现 `app/windows/tools/KeyBeacon.Probe/Checks.cs`：P1–P6 检查、原始字节 hex、逐调用耗时，输出 JSON run log（CLI-3）
- [ ] T023 🖥️ 在 Windows + Corne 上执行 probe，把 verdict/checks 回填 `specs/003-windows-desktop-client/research.md` §5，并据 P6 实测值确定 `--timeout` 默认（SC-006）

**Checkpoint**: probe verdict=PASS，门禁开，可进入用户故事实现。

---

## Phase 4: User Story 1 - 实时层与修饰键（Priority: P1）🎯 MVP

**Goal**: 托盘常驻 + 置顶悬浮窗，实时显示当前层名与 Shift/Control/Alt/Gui 指示器。

**Independent Test**: quickstart S1；KBP 1.0 键盘连接后切层/按修饰键，显示 3 秒内更新，空层名回退 `L{index}`。

### Implementation for User Story 1

- [X] T024 [US1] 实现 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs`：`DeviceWatcher` 跟踪已连接设备、连接选定键盘、发现 AA1、`WriteClientCharacteristicConfigurationDescriptorAsync(Notify)` 订阅（C-1/C-2/C-3）
- [X] T025 [US1] 实现 `app/windows/src/KeyBeacon.App/Ui/TrayController.cs`：`H.NotifyIcon.Wpf` 托盘图标 + 菜单（含"详细日志"可勾选项，绑定 `AppSettings.VerboseLogging`，FR-024），不占任务栏、不抢焦点（FR-008）
- [X] T026 [US1] 实现 `app/windows/src/KeyBeacon.App/Ui/FloatingPanel.xaml` 与 `app/windows/src/KeyBeacon.App/Ui/FloatingPanel.xaml.cs`：无边框、`Topmost`、`ShowInTaskbar=false` 常驻悬浮窗（FR-020）
- [X] T027 [US1] 实现 `app/windows/src/KeyBeacon.App/Ui/MainViewModel.cs`：绑定层名 + 四个修饰键指示器（由 `KeyboardStatus` 合并位派生）
- [X] T028 [US1] 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs` 接 `ValueChanged` → `KeyboardStatus.Parse` → 更新 `app/windows/src/KeyBeacon.App/Ui/MainViewModel.cs`；空名回退 `L{index}`；状态未变化不刷新（FR-004/FR-006）
- [X] T029 [US1] 在 `app/windows/src/KeyBeacon.App/Settings/AppSettings.cs` 落地显示模式（full/compact）与钉角，并驱动 `app/windows/src/KeyBeacon.App/Ui/FloatingPanel.xaml` 布局/定位（对标 macOS 完整/精简）

**Checkpoint**: 仅依赖 Phase 1–3，US1 独立可用（MVP，一把 KBP 1.0 键盘即获"显示屏"）。

---

## Phase 5: User Story 2 - 诚实降级（Priority: P2）

**Goal**: 断开/蓝牙不可用/陈旧/不支持 MAJOR 时显示诚实状态，绝不展示过时或伪造读数。

**Independent Test**: quickstart S2；断开后 3 秒内切"未连接"；关蓝牙显"蓝牙不可用"；不支持 MAJOR 显"协议版本不受支持"。

### Implementation for User Story 2

- [X] T030 [US2] 实现 `app/windows/src/KeyBeacon.App/Ble/StalenessCoordinator.cs`：1Hz tick 驱动 `StalenessTracker`；字段跨 live→stale（连接仍在）时保留最后已知值 + 渲染"更新于 hh:mm:ss" + 视觉弱化（FR-007a），并发 `staleness.field_stale`；stale→live 发 `field_live`（C-4）
- [X] T031 [US2] 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs` + `app/windows/src/KeyBeacon.App/Ui/MainViewModel.cs` 处理断开/蓝牙不可用：`ForceStaleAll()` 立即标记全字段陈旧 + 3 秒内切"未连接"并停显旧值（区别于 FR-007a 的连接内陈旧），发 `connection.state_changed`（FR-007/SC-003）
- [X] T032 [US2] 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs` 处理蓝牙适配器关闭/缺失 → UI 显示"蓝牙不可用"，开启后自动恢复发现（US2 场景 2 + edge case）
- [X] T033 [US2] 在 `app/windows/src/KeyBeacon.App/Ui/MainViewModel.cs` 处理 `KbpUuids.Classify` 返回 `unsupportedVersion` → 显示"协议版本不受支持"且不解析（FR-009）
- [X] T034 [US2] 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs` 断开后经 `DeviceWatcher` 自动重连/重新发现，无需重启；处理锁屏/休眠唤醒恢复（FR-011）

**Checkpoint**: US1 + US2 独立可用；降级路径每个事件恰好一条结构化日志。

---

## Phase 6: User Story 5 - 连接与电量 KBP 1.1（Priority: P2）

**Goal**: 按能力位显示 KBP 1.1 连接/电量；不支持字段完全隐藏；哨兵显"不可用"。

**Independent Test**: quickstart S3；KBP 1.1 分体键盘按能力位显示左右半电量/连接；255 显"不可用"；仅 1.0 键盘整块不出现。

### Implementation for User Story 5

- [X] T035 [US5] 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs` 发现 AA2/AA3 并按存在性判定 `ProtocolVariant`（仅 AA1→1.0；AA2→1.1(hasBattery=AA3存在)）；见 AA2 无 AA1 发 `discovery.anomaly`
- [X] T036 [US5] 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs` 订阅 AA2/AA3 通知并解析 `ConnectivityStatus`；AA3 解析 MUST 传入 AA2 的 `isSplit`（缓存 AA3 待 capability 已知，C-3）
- [X] T037 [US5] 在 `app/windows/src/KeyBeacon.App/Ui/FloatingPanel.xaml` 按 `CapabilityMatrix` 位做字段级显示/隐藏（FR-016/SC-008）；`IsConsistent=false` 丢弃违背位并发 `capability.inconsistent`
- [X] T038 [US5] 在 `app/windows/src/KeyBeacon.App/Ui/FloatingPanel.xaml` 渲染电量：`Percent`→百分比，`Unavailable`→"不可用"（禁止 0% 伪造），越界发 `battery.out_of_range`（FR-017/SC-009）
- [X] T039 [US5] 在 `app/windows/src/KeyBeacon.App/Ui/FloatingPanel.xaml` 渲染连接字段：主机链路、BLE profile（index/maxSlots/open）、分体左右在线、输出端点（usb/ble/unknown）、充电标志

**Checkpoint**: US1/US2/US5 独立可用；1.1 展示严格受能力位约束。

---

## Phase 7: User Story 6 - 诊断日志收集（Priority: P2）

**Goal**: 一键导出含环境信息的诊断包，供开源 issue 排障。

**Independent Test**: quickstart S5；托盘菜单 ≤3 步导出 `.zip`（environment.json + 近期日志 + README.txt）；详细模式含失败 payload hex；重启后仍含旧日志；地址/标识符不明文。

### Implementation for User Story 6

- [X] T040 [US6] 实现 `app/windows/src/KeyBeacon.App/Diagnostics/DiagnosticsExporter.cs`：托盘菜单动作 → `System.IO.Compression` 打包 `.zip`（environment.json + logs/ 副本 + README.txt），≤3 步（SC-011，契约 `contracts/diagnostics-bundle.md`）
- [X] T041 [US6] 生成 `environment.json`：appVersion、osVersion/build、arch、dotnetRuntime、bluetoothAdapter（型号+开关，略地址）、detectedKbpVersion、keyboards[]（displayName/形态/连接/能力位 hex）
- [X] T042 [US6] 在 `app/windows/src/KeyBeacon.App/Diagnostics/DiagnosticsLogger.cs` 接入详细模式开关：verbose 记录成功路径 + 原始 payload 每次 hex + GATT 概览 + async 耗时；常规不记 payload（FR-024）
- [X] T043 [US6] 在 `app/windows/src/KeyBeacon.App/Diagnostics/DiagnosticsExporter.cs` 脱敏与知情：默认省略/哈希蓝牙地址与 Id，设备名默认打码（`Corne-***(n)`）；导出前审阅对话框呈现将含信息，用户确认后再写盘（FR-025/US6 场景 3）
- [X] T044 [P] [US6] 编写包内 `app/windows/src/KeyBeacon.App/Diagnostics/README.txt`（中英双语）：说明内容、可识别信息与脱敏策略、维护者阅读指引（Principle VI）

**Checkpoint**: 用户可离线产出可分享诊断包，维护者据包定位典型问题（SC-012）。

---

## Phase 8: User Story 3 - 多键盘选择（Priority: P3）

**Goal**: 多把 KBP 键盘时选择监视对象并记忆。

**Independent Test**: quickstart S4；两把键盘按设备名列出，选定后 ≤10 秒显其状态，重启沿用。

### Implementation for User Story 3

- [X] T045 [US3] 在 `app/windows/src/KeyBeacon.App/Ui/TrayController.cs` 列出所有 `supported` 键盘子菜单，用 `CompatibleKeyboard.DisplayName`（FR-010/SC-007）
- [X] T046 [US3] 在 `app/windows/src/KeyBeacon.App/Settings/AppSettings.cs` 写入选择 `SelectedKeyboardId`；启动在 `app/windows/src/KeyBeacon.Core/CompatibleKeyboard.cs` 用 `ResolveSelection(candidates, remembered)` 决定监视对象
- [X] T047 [US3] 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs` 切换选择时重建订阅并刷新 UI，≤10 秒内显示目标键盘状态

**Checkpoint**: 多键盘独立可用，与 US1/US5 展示层无冲突。

---

## Phase 9: User Story 4 - Linux 尽力而为（Priority: P4，不阻塞）

**Goal**: 探查 Linux 可行性并据实记录结论，不影响 Windows 交付。

**Independent Test**: 在 Linux 主机跑 `conformance/conformance_tool.py` 判断能否枚举已连接 KBP 键盘并读/订阅。

### Implementation for User Story 4

- [ ] T048 🖥️ [US4] 在 Linux 主机用 `conformance/conformance_tool.py` 验证枚举已连接 KBP 键盘 + 读/订阅状态，记录 BlueZ/内核 HID 冲突结论（复用既有资产，不新写 GUI）
- [ ] T049 [US4] 将 Linux 结论（可交付/降级/延后）写入 `specs/003-windows-desktop-client/research.md`，明确 Windows 交付不受影响（FR-015）

**Checkpoint**: Linux 结论有据可查；Windows 主线不受阻。

---

## Phase 10: Polish & Cross-Cutting

- [ ] T050 [P] 运行 `dotnet test app/windows/tests/KeyBeacon.Core.Tests/KeyBeacon.Core.Tests.csproj` 全绿（SC-005：共享测试向量 100% 通过）
- [ ] T051 🖥️ [P] 在 Windows 上按 `specs/003-windows-desktop-client/quickstart.md` 执行 S1–S6 端到端验收剧本
- [X] T052 [P] macOS 零回归：在 macOS 主机对 `app/macos/Package.swift` 工程 `swift test` 全绿（SC-004）
- [X] T053 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs` 核对性能/降噪：状态未变化不产生多余刷新/流量（FR-006），空闲零噪声日志
- [ ] T054 [P] 若新增面向键盘作者的公开 Windows 文档，则按 Principle VI 在 `docs/windows-client.md` 写英中双语（内部 spec/plan 不受此约束）

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 无依赖，可立即开始
- **Foundational (Phase 2)**: 依赖 Setup 完成 — **阻塞所有用户故事**
- **Phase 0 Probe (Phase 3)**: 依赖 Phase 2（复用 `KeyBeacon.Core`）— **阻塞所有用户故事实现（门禁）**
- **User Stories (Phase 4–9)**: 依赖 Phase 2 + Phase 3 完成
  - 之后可按优先级顺序（US1→US2→US5→US6→US3→US4）或并行（有人力时）
- **Polish (Phase 10)**: 依赖目标用户故事完成

### User Story Dependencies

- **US1 (P1)**: Phase 3 后可开始，无跨故事依赖 — MVP
- **US2 (P2)**: Phase 3 后可开始；与 US1 展示层集成但可独立测
- **US5 (P2)**: Phase 3 后可开始；依赖 US1 的监视/展示骨架（集成点）
- **US6 (P2)**: Phase 3 后可开始；仅依赖诊断基础设施（Phase 2 的 T016/T017）
- **US3 (P3)**: 依赖 US1 的监视层；可独立测
- **US4 (P4)**: 独立；复用 `conformance/`，不依赖 Windows 实现

### Within Each User Story

- 模型（Core）先于服务（BLE）先于 UI
- 每故事完成再进下一优先级（或按团队并行）
- [P] 任务分属不同文件，可同时进行

### Parallel Opportunities

- Phase 1 所有 [P] 任务并行
- Phase 2 解析实体 T006–T012 并行；测试 T013–T015 并行；基础设施 T016–T019 并行
- Phase 3 T021 与 T020 并行（不同文件）
- Phase 3 后多故事并行（人力足够时）：US1 / US5 / US6 可同时开工

---

## Parallel Example: Phase 2（解析器并行）

```bash
# 不同文件的纯实体可同时实现：
Task: "KbpUuids.cs — UUID + Classify"          # T006
Task: "KeyboardStatus.cs — 层/修饰键解析"        # T007
Task: "CapabilityMatrix.cs — 能力位"           # T008
Task: "ConnectivityStatus.cs — 7 字节位域"      # T009
Task: "BatteryStatus.cs — overall/split"      # T010
Task: "StalenessTracker.cs — 3s 陈旧"          # T011
Task: "CompatibleKeyboard.cs — 设备视图/选择"   # T012
```

---

## Implementation Strategy

### MVP First（仅 US1）

1. Phase 1 Setup → 2. Phase 2 Foundational（`dotnet test` 全绿）→ 3. **Phase 3 Probe 门禁（真机 PASS）** → 4. Phase 4 US1
5. **STOP & VALIDATE** quickstart S1 独立验收 → 可交付 MVP

### Incremental Delivery

1. Setup + Foundational + Probe → 地基就绪
2. + US1 → 验收（MVP）
3. + US2（诚实降级）→ 验收
4. + US5（1.1 连接/电量）→ 验收
5. + US6（诊断包）→ 验收
6. + US3（多键盘）→ 验收
7. + US4（Linux 探查，非阻塞）→ 记录结论
8. Polish

### 关键风险点

- **Phase 3 是硬门禁**：P3（GATT 不踢 HID）若 FAIL，按 research.md §3 回退（短连接/按需快照/降级），可能影响 SC-002 实时性目标 — 必须真机结论，禁止臆测。
- 所有 🖥️ 任务无法在 macOS 主机完成，需 Windows + 参考键盘。

---

## Notes

- [P] = 不同文件、无未完成依赖
- [Story] 标签映射到 spec.md 用户故事，保证可追溯
- 解析层测试必需（SC-005/FR-013）；BLE/UI 以 quickstart 手工剧本 + probe 真机验收
- 每故事独立可完成、可验证；建议每个任务或逻辑组后提交
- 避免：模糊任务、同文件冲突、破坏独立性的跨故事依赖
