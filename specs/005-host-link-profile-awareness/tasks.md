---

description: "Task list for 005-host-link-profile-awareness"
---

# Tasks: 每连接主机上下文（Per-Link Host Context）

**Input**: Design documents from `specs/005-host-link-profile-awareness/`

**Prerequisites**: plan.md ✅、spec.md ✅、research.md ✅、data-model.md ✅、contracts/（host-link-context.md、consumer-flow.md）✅、quickstart.md ✅

**Tests**: spec 的 FR-014 明确要求「解析与状态分类逻辑必须有无需 BLE 硬件的纯函数单测，且 wire→五态映射穷举」，故**包含测试任务**（test-first）。

**Organization**: 按用户故事（US1/US2/US3）分组，每组可独立实现与测试。承载方式 = 方案 A（新增独立只读特征 `AA440AA4-…`）。

> **跨仓库说明**：固件生产者（AA4 只读特征的 READ 处理器）在兄弟仓库 `zmk-keybeacon`，**不在本仓库 tasks 范围**。本仓库交付：`protocol/` 契约 + `conformance/` 向量 + macOS/Windows 两端消费者。端到端剧本（quickstart）需固件就绪，列为外部依赖。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: US1 / US2 / US3（Setup/Foundational/Polish 无标签）

## Path Conventions（取自 plan.md Project Structure）

- macOS 纯逻辑：`app/macos/Sources/BleWidgetCore/`；平台层：`app/macos/Sources/BleWidget/`；测试：`app/macos/Tests/BleWidgetTests/`
- Windows 纯逻辑：`app/windows/src/KeyBeacon.Core/`；应用层：`app/windows/src/KeyBeacon.App/`；测试：`app/windows/tests/KeyBeacon.Core.Tests/`
- 协议：`protocol/`；一致性：`conformance/`

---

## Phase 1: Setup（共享基础）

**Purpose**: 建立回归基线与两端共享常量

- [X] T001 校验两端基线通过：`cd app/macos && swift test` 与 `cd app/windows && dotnet test tests/KeyBeacon.Core.Tests/KeyBeacon.Core.Tests.csproj` 均绿，作为 SC-004 向后兼容回归对照基线
- [X] T002 [P] 新增 AA4 UUID 常量 `AA440AA4-F5ED-4C48-84A1-8062D20D3D55` 到 macOS `app/macos/Sources/BleWidget/BLEClient.swift`（UUID 常量区 :53-64）
- [X] T003 [P] 新增 AA4 UUID 常量到 Windows `app/windows/src/KeyBeacon.Core/KbpUuids.cs`（与 service/AA1/AA2/AA3 并列）

---

## Phase 2: Foundational（阻塞前置 —— 宪法「protocol 先行」）

**Purpose**: 协议契约与共享测试向量是两端实现的唯一真相源，MUST 先行（宪法 §I/§V + Development Workflow）

**⚠️ CRITICAL**: 本阶段完成前，任何 US 的 app 实现不得开始

- [X] T004 在 `protocol/README.md` 新增 AA4 只读特征定义（英文侧）：§14.2 特征表增 `AA440AA4-…`（属性 `READ` only、无 CCC）、新增小节描述 payload `[0].bits0–6 = local_link_profile`（1-based，0=未确定）、`[0].bit7` reserved MUST 0、§14.5 发现流程增「发现 AA4 → READ」、§11/§13 引用，依据 `specs/005-host-link-profile-awareness/contracts/host-link-context.md`
- [X] T005 在 `protocol/README.md` 补齐上述增量的**中文镜像**（§VI 双语：MUST→必须 / SHOULD→应 / MAY→可），与英文逐段对应
- [X] T006 更新 `protocol/VERSION`（`1.1.0`→`1.2.0`）并在 `protocol/CHANGELOG.md` 增 1.2.0 条目（英中双语，说明「新增可选只读特征 AA4，既有特征字节不变」）
- [X] T007 在 `conformance/checklist.md` 增 C13/C14（英中双语）：C13=AA4 存在则属性恰为 READ（无 NOTIFY/无 CCC）且 payload≥1 字节、`[0].bit7=0`；C14=`[0].bits0–6 ∈ {0}∪[1,profile_max_slots]`
- [X] T008 [P] 在 `conformance/conformance_tool.py` 新增 `parse_link_slot(data)` 与 AA4 特征属性/长度校验（实现 C13/C14；无 AA4 则 SKIP）
- [X] T009 [P] 在 `conformance/tests/` 新增 `test_us5_link_slot.py`（或并入既有）：穷举 slot=0/1..max、bit7 被忽略、空包返回 None、越界检测

**Checkpoint**: 协议契约 + 共享向量就绪，两端消费者可开工

---

## Phase 3: User Story 1 - 多机消歧义「此电脑」状态（Priority: P1）🎯 MVP

**Goal**: 键盘绑定两台机、切换 active profile 时，每台机的「此电脑」状态在 ≤1s 内正确显示 in-use-here / active-elsewhere(N)，绝不在非活跃机显示 in-use。

**Independent Test**: 一键盘绑两台电脑，在键盘上循环切换 active slot；每台机状态 ≤1s 跟随，非接收机永不显示「在此使用」。

### Tests for User Story 1（test-first；若类型未建，先建最小骨架使其编译，再确保断言 FAIL）⚠️

- [X] T010 [P] [US1] macOS `LinkSlot` 解析穷举单测 in `app/macos/Tests/BleWidgetTests/HostLinkProfileAwarenessTests.swift`：单字节 slot/bit7 忽略/空包→nil/越界
- [X] T011 [P] [US1] macOS 五态派生 `deriveLocalHostStatus` 穷举单测（同文件）：输入 {hasAA4,connected,output,active(index/open),localSlot} × 五态全组合，含优先级（disconnected>onUsb>in-use/elsewhere>cannotDetermine）
- [X] T012 [P] [US1] Windows `LinkSlot` 解析穷举单测 in `app/windows/tests/KeyBeacon.Core.Tests/HostContextStatusTests.cs`（复用 `Payload(...)` 模式）
- [X] T013 [P] [US1] Windows 五态派生 `DeriveLocalHostStatus` 穷举单测（同文件），与 macOS 用例一一对应（跨平台 parity，宪法 §III）

### Implementation for User Story 1

- [X] T014 [P] [US1] macOS 新建 `app/macos/Sources/BleWidgetCore/LinkSlot.swift`：纯函数 `parse(Data)->LinkSlot?`（`slot = data[0] & 0x7F`，`data.count<1`→nil，bit7/尾部忽略）
- [X] T015 [P] [US1] Windows 新建 `app/windows/src/KeyBeacon.Core/LinkSlot.cs`：record + `Parse(ReadOnlySpan<byte>)->LinkSlot?`，语义同 macOS
- [X] T016 [P] [US1] macOS 新建 `app/macos/Sources/BleWidgetCore/LocalHostStatus.swift`：五态枚举 `inUseHere/activeElsewhere(slot)/onUsb/cannotDetermine/disconnected` + 纯函数 `deriveLocalHostStatus(hasAA4,cap,link,active,local,output)`（按 data-model §6.1）
- [X] T017 [P] [US1] Windows 新建 `app/windows/src/KeyBeacon.Core/HostContextStatus.cs`：五态枚举 + `DeriveLocalHostStatus(...)`，逻辑逐行对齐 macOS
- [X] T018 [US1] macOS `app/macos/Sources/BleWidgetCore/BLEClient.swift`：AA4 加入 `discoverCharacteristics`、`didDiscoverCharacteristicsFor` 保存引用并 `readValue(for: aa4)`（只读不订阅）、`didUpdateValueFor` 按 `uuid==AA4` 分发到新 `handleLinkSlotRead`，缓存 AA2/AA4 并经 `recomputeHostStatus` 派生五态 → 新增 delegate `didUpdateHostStatus`（依赖 T002、T014、T016）
- [X] T019 [US1] Windows `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs`：发现 AA4、`ReadAsync(_linkSlotChar)` 只读解析（不订阅 NOTIFY），经 `KeyboardSnapshot` 携带 host context（依赖 T003、T015、T017）
- [X] T020 [US1] Windows 在 `app/windows/src/KeyBeacon.App/Ble/KeyboardSnapshot.cs` 增 `HostStatus`（`LocalHostStatus?` 可空=隐藏）字段（供 UI 绑定；依赖 T017）
- [X] T021 [P] [US1] macOS 五态双语文案：`app/macos/Sources/BleWidgetCore/Localization.swift` 英表+中表各增 5 key（in-use/elsewhere(P{N})/on-usb/cannot-determine/disconnected）
- [X] T022 [P] [US1] Windows 五态双语文案：`app/windows/src/KeyBeacon.App/Localization/Resources.resx` 与 `Resources.zh-CN.resx` 各增同 5 key
- [X] T023 [US1] macOS `app/macos/Sources/BleWidget/FloatingPanel.swift`：新增独立 `localHostRow`（置于卡片首行）按 `LocalHostStatus` 五态分支渲染「此电脑」行，与键盘全局状态视觉区分；`update(hostStatus:)` 入口（依赖 T016、T021）
- [X] T024 [US1] Windows `app/windows/src/KeyBeacon.App/Ui/MainViewModel.cs` `ApplyHostStatus` + `FloatingPanel.xaml` 独立 per-link 行：五态渲染分支（依赖 T020、T022）
- [X] T025 [P] [US1] macOS 诊断：`app/macos/Sources/BleWidget/DiagnosticsLogger.swift` `Connection` category 增 `hostlink.unresolved`/`hostlink.cannot_determine`
- [X] T026 [P] [US1] Windows 诊断：`app/windows/src/KeyBeacon.App/Diagnostics/DiagnosticsLogger.cs` 事件常量(:39-69)增 `hostlink.unresolved`/`hostlink.cannot_determine`
- [X] T027 [US1] 两端把派生与断连接入诊断：断连 → `disconnected` 覆盖并 `connection.state_changed`；slot=0 → `hostlink.unresolved`；输入不足 → `hostlink.cannot_determine`（各恰一条，FR-013）（依赖 T018/T019/T025/T026）

**Checkpoint**: US1 可独立验收 —— 双机切换 ≤1s 正确翻转，非接收机永不「在此使用」（SC-001）

---

## Phase 4: User Story 2 - 零配置自动学习本机 slot（Priority: P2）

**Goal**: 用户零配置；app 连接/重连时自动从 AA4 学到本机 slot，会话内记忆；键盘重新配对到别的 slot 后重连自动纠正。

**Independent Test**: 全新安装（无设置）连已绑定键盘，首屏状态正确且无需输入 slot；重新配对到另一 slot 重连后自动报新 slot。

### Tests for User Story 2 ⚠️

- [X] T028 [P] [US2] macOS 重读/重学单测 in `app/macos/Tests/BleWidgetTests/HostLinkProfileAwarenessTests.swift`：模拟 slot 由 N→M，验证缓存刷新与 `learnedAt` 更新
- [X] T029 [P] [US2] Windows 重读/重学单测 in `app/windows/tests/KeyBeacon.Core.Tests/HostContextStatusTests.cs`，用例对齐 macOS

### Implementation for User Story 2

- [X] T030 [US2] macOS 新增公开 `readLinkSlot()` 于 `app/macos/Sources/BleWidget/BLEClient.swift`（`peripheral?.readValue(for: linkSlotCharacteristic)`），供重读（依赖 T018）
- [X] T031 [US2] macOS 接入重读时机于 `BLEClient.swift`：reconnect、AA2 `profile_open` 1→0、AA2 notify 中 `active_index` 变化、60s 兜底 timer（依赖 T030）
- [X] T032 [US2] Windows 接入重读时机于 `app/windows/src/KeyBeacon.App/Ble/KeyboardMonitor.cs`：`ReconnectAsync`(:100-104)/`OnConnectionStatusChanged`(:386-396)、profile_open 1→0、active 变化、60s 兜底（复用 `ReadAsync`，依赖 T019）
- [X] T033 [P] [US2] 两端 `LinkSlot` 会话级缓存 + `learnedAt`；重连清缓存重学（macOS `BLEClient.swift`、Windows `KeyboardMonitor.cs`）
- [X] T034 [P] [US2] 两端 `hostlink.read_back_slot` 信息级诊断（读回刷新且与缓存不同时各一条）：macOS `DiagnosticsLogger.swift`、Windows `DiagnosticsLogger.cs`

**Checkpoint**: US2 可独立验收 —— 零配置首屏正确（SC-002）、重新配对自动纠正

---

## Phase 5: User Story 3 - 老固件/老 app 保持不变（Priority: P3）

**Goal**: 新 app + 老固件（无 AA4）仅显示 link 级、不臆造；老 app + 新固件（有 AA4）既有字段字节级不变、无新 UI。

**Independent Test**: (a) 新 app 对无 AA4 的键盘不显示 in-use/elsewhere；(b) 上一版 app 对有 AA4 的键盘解析 AA0/AA1/AA2/AA3 字节级一致。

### Tests for User Story 3 ⚠️

- [X] T035 [P] [US3] 两端「未发现 AA4 → cannotDetermine、不臆造」单测（macOS/Windows 测试文件各一用例，hasAA4=false 分支）
- [X] T036 [P] [US3] `conformance/tests/` 增向后兼容向量：老固件（无 AA4，SKIP C13/C14 不失败）、AA4 存在但无 AA2（`discovery.anomaly`）

### Implementation for User Story 3

- [X] T037 [US3] 两端发现流程：有 AA4 无 AA2 → 发 `discovery.anomaly` 并按不可用处理（macOS `BLEClient.swift`、Windows `KeyboardMonitor.cs`）
- [X] T038 [US3] 回归确认：既有 `ConnectivityStatus`(macOS `.swift`/Windows `.cs`) 与 `CapabilityMatrix` **零改动**；重跑 T001 基线用例保持全绿（SC-004）

**Checkpoint**: 三个 US 均可独立验收；兼容矩阵（quickstart D）通过

---

## Phase 6: Polish & Cross-Cutting

**Purpose**: 跨故事验证与端到端

- [X] T039 [P] 运行 `python3 conformance/conformance_tool.py` 与 `python3 -m pytest conformance/tests/ -q`，确认 C1–C14 无新失败（SC-005）
- [X] T040 [P] 两端完整单测绿：`swift test`（macOS）、`dotnet test`（Windows），覆盖率包含五态穷举
- [X] T041 跨平台 parity 复核（宪法 §III）：逐条对比两端五态文案与行为、诊断事件名一致
- [ ] T042 端到端真机验收（需 `zmk-keybeacon` 1.2 固件就绪）：按 quickstart S1–S6 + 降级负测矩阵 C 表，参考键盘 + 第二台电脑，确认 ≥20 次切换无卡滞（SC-001/SC-003）
  - ⏸ **阻塞于硬件**：需真机 + 第二台电脑，无法在 CI/开发机完成。
  - 诊断背景：上线反馈的「切 profile 回来后未连接/无法确定/P5」已用 CoreBluetooth 探针直读证实**固件侧正确**（AA4=slot1 稳定），根因为 App 仅在 discovery 读一次 AA4、链路不断线时不重读（首连 slot 未解析/重配对后变 stale）。本次 US2（T030–T034）补齐的「active 变化 / open→assigned / 60s 兜底 / reconnect 重读 AA4 + 会话缓存」即针对该根因；重启 App 可恢复的现象已侧面验证修复方向。真机回归请覆盖：首连 slot=0→解析、P1↔P5 往返、重配对到新 slot。
- [X] T043 [P] 若根 `README.md` 提及协议版本/能力，按 §VI 双语更新 1.2

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (P1)**：无依赖，立即开始
- **Foundational (P2)**：依赖 Setup；**阻塞所有 US**（协议契约 + 向量是两端真相源）
- **US1 (P3)**：依赖 Foundational；MVP
- **US2 (P4)**：依赖 Foundational + US1 的状态面（读 AA4 + 派生 + UI 已在）
- **US3 (P5)**：依赖 Foundational + US1（兼容分支基于五态派生的 hasAA4=false 路径）
- **Polish (P6)**：依赖所需 US 完成；T042 额外依赖外部固件仓库

### User Story Dependencies

- **US1**：Foundational 后即可，无其他故事依赖
- **US2**：建立在 US1 的读/派生/UI 之上，但「零配置/重学」可独立测试
- **US3**：复用 US1 的 hasAA4=false 分支，可独立测试

### Within Each User Story

- 测试先写并 FAIL（编译语言允许先建最小类型骨架）
- 纯类型（LinkSlot/五态）先于 BLE 接入；BLE 接入先于 UI 渲染；文案可与逻辑并行
- 诊断接入在读/派生路径就位后

### Parallel Opportunities

- Setup：T002（macOS 常量）∥ T003（Windows 常量）
- Foundational：T008（工具）∥ T009（向量）（T004–T007 协议文档顺序相关）
- US1 测试：T010 ∥ T011 ∥ T012 ∥ T013
- US1 纯类型：T014 ∥ T015 ∥ T016 ∥ T017；文案 T021 ∥ T022；诊断 T025 ∥ T026
- 两端（macOS/Windows）天然不同文件，几乎全程可双线并行

---

## Parallel Example: User Story 1

```bash
# 测试先行（四个测试文件/用例并行）：
Task T010: macOS LinkSlot 解析单测
Task T011: macOS 五态派生穷举单测
Task T012: Windows LinkSlot 解析单测
Task T013: Windows 五态派生穷举单测

# 纯类型并行（不同文件）：
Task T014: macOS LinkSlot.swift
Task T015: Windows LinkSlot.cs
Task T016: macOS LocalHostStatus.swift
Task T017: Windows HostContextStatus.cs
```

---

## Implementation Strategy

### MVP First（仅 US1）

1. Phase 1 Setup → 2. Phase 2 Foundational（协议+向量，CRITICAL）→ 3. Phase 3 US1 → **STOP & VALIDATE**：双机切换 ≤1s 正确（SC-001）→ 可演示 MVP。

### Incremental Delivery

Setup+Foundational → US1（MVP，消歧义）→ US2（零配置+重学）→ US3（兼容）→ Polish（一致性+端到端）。每步不破坏前序。

### Parallel Team Strategy

Foundational 完成后：开发者 A 做 macOS 线、开发者 B 做 Windows 线（不同文件，天然并行），以 `conformance/` 向量为对齐基准。

---

## Notes

- [P] = 不同文件、无未完成依赖
- 固件（AA4 READ 生产者）在 `zmk-keybeacon` 兄弟仓库，不在本 tasks；T042 端到端依赖其 1.2 固件
- 既有 `ConnectivityStatus`/`CapabilityMatrix` **零改动**是本方案（方案 A）的硬约束，T038 专门回归确认
- 每个 US 可停在 checkpoint 独立验收
- 每个任务或逻辑组完成后提交
