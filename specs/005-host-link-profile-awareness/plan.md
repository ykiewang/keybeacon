# Implementation Plan: 每连接主机上下文（Per-Link Host Context）

**Branch**: `005-host-link-profile-awareness` | **Date**: 2026-11-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/005-host-link-profile-awareness/spec.md`

## Summary

解决「键盘同时绑定多台电脑，两端都误显示『在用』」的歧义。根因：KBP 1.1 Connectivity 特征通过**广播 NOTIFY** 下发、各主机字节相同，`profile_index` 只报**全局活跃** slot。本 feature 利用 GATT **READ 的 per-connection 特性**（已验证：Zephyr GATT read callback 带 `struct bt_conn *conn`）——固件能识别是哪条链路在问，可对每台主机返回**不同**的 `local_link_profile`——于是每台主机**零配置**学到「我是 P几」，再与广播的 `active_profile_index` 比对，得出五态：`in-use-here` / `active-elsewhere(N)` / `on-usb` / `cannot-determine` / `disconnected`。

技术路线 = **协议 MINOR 演进（KBP 1.1→1.2）+ 两端原生消费者实现**，承载方式采用**方案 A：新增独立只读特征 `AA440AA4-…`**：
- **wire**：新增可选特征 `AA440AA4-…`（**`READ` only，无 NOTIFY**），payload `[0]` 携带 `local_link_profile`（1-based，0=未确定）。**既有 AA0/AA1/AA2/AA3 一个字节都不改。** 属合法 MINOR（§9/§14.6「新增可选特征」）。
- **为何只读特征**：只读特征物理上不会推送 NOTIFY，host 读回**必然**是本连接 READ 响应，**从根上消除 host 侧「区分 READ 帧与广播 NOTIFY 帧」的竞态**（CoreBluetooth 两者共用同一回调，是被否决方案的最大脆弱点）。能力探测走「特征是否存在」，与 1.1 探测 AA2/AA3 一致。
- **生产者**：固件在兄弟仓库 `zmk-keybeacon`（新 MINOR 发布），AA4 READ 返回本连接 slot、无法解析时发 0。
- **消费者**：macOS（CoreBluetooth/AppKit）与 Windows（WinRT/WPF）各实现一份**同构纯函数** `deriveLocalHostStatus`，共用 `conformance/` 测试向量。
- **见证**：`conformance/checklist.md` 增 C13/C14；`protocol/` 中英双语更新。

## Technical Context

**Language/Version**:
- macOS：Swift 5.9+（`app/macos/`，`BleWidgetCore` 纯逻辑 + `BleWidget` 平台层）
- Windows：C# 12 / .NET 8（`app/windows/`，`KeyBeacon.Core` `net8.0` + `KeyBeacon.App` `net8.0-windows10.0.19041.0`）

**Primary Dependencies**:
- macOS：CoreBluetooth、AppKit（既有）
- Windows：WinRT `Windows.Devices.Bluetooth*`、WPF（既有）
- 一致性：`conformance/conformance_tool.py`（bleak，跨平台）

**Storage**: N/A（`local_link_profile` 为**会话级内存缓存**，不落盘；避免「上次 slot」误导，见 data-model §7）。

**Testing**:
- 纯函数单测：macOS XCTest（`app/macos/Tests/BleWidgetTests/`）、Windows xUnit（`app/windows/tests/KeyBeacon.Core.Tests/`），**无需蓝牙硬件**（FR-014）。
- 一致性：`conformance/conformance_tool.py` + `pytest conformance/tests/`。
- 端到端：quickstart Given/When/Then（参考键盘 + 第二台电脑）。

**Target Platform**: macOS 12+；Windows 10 2004（build 19041）+ / Windows 11，x64+ARM64。

**Project Type**: 协议增量 + 双平台桌面应用消费者（跨仓库：固件在 `zmk-keybeacon`）。

**Performance Goals**: active profile 变化 → 「此电脑」状态更新 ≤ 1 s（FR-006/SC-001）。

**Constraints**:
- MINOR 演进：仅**新增**可选特征，既有特征字节级不变，service UUID 不变（宪法 §II）。
- 每降级事件恰好一条结构化诊断（宪法 §IV / FR-013）。
- UI 中英双语（FR-010）；protocol/ 与 conformance/ 规范文档英中双语（宪法 §VI / FR-015）。
- 固件无法解析 peer→slot 时必须发「未确定」（0）而非猜测（FR-003）。

**Scale/Scope**: 两端各新增约 1 个只读特征发现+读取、1 个 `LinkSlot` 解析纯类型、1 个五态派生纯函数、1 个状态枚举、5 个 L10n 键；协议文档新增 1 个可选特征；**既有解析器零改动**。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

依据 `.specify/memory/constitution.md v1.1.0`（6 原则 + Platform Scope & Delivery + Testing & Verification Discipline + Governance）逐条评估。

| 原则 | 结论 | 证据 |
|------|------|------|
| **I. Wire-Contract Self-Containment** | ✅ PASS | 增量先在 `specs/005/contracts/host-link-context.md` 起草，ratify 后并入 `protocol/README.md §14`（唯一真相源）。AA4 的 UUID/属性/payload 可仅凭协议文档实现；不改 `app/**` 反哺协议。 |
| **II. Backward Compatibility is Non-Negotiable** | ✅ PASS | **方案 A 为纯加法**：service UUID 不变、AA0/AA1/AA2/AA3 字节级不变、AA4 为新增可选特征。新老双向兼容（FR-011/012，SC-004）；老 app 根本不发现 AA4。 |
| **III. Identity From Protocol, Not Branding** | ✅ PASS | per-link 能力由 **AA4 特征存在性**（结构能力）判定，无型号白名单。 |
| **IV. Observable Degradation Over Guessing** | ✅ PASS | 五态派生（data-model §6）：无正向确认 → `cannot-determine`/`disconnected`，绝不臆造 in-use/elsewhere（FR-008/009）；每降级恰一条诊断（FR-013）。 |
| **V. Spec-First Development (NON-NEGOTIABLE)** | ✅ PASS | 本 feature 正走 specify→plan→tasks→analyze；contracts 为 drafting ground，protocol/ 由契约 ratify 后更新。 |
| **VI. Bilingual Normative Docs** | ✅ PASS（强制） | 发布协议增量 → `protocol/README.md`、`protocol/CHANGELOG.md`、`conformance/checklist.md` MUST 英中双语（FR-015）。`specs/` 内部文档豁免。 |
| **Platform Scope & Delivery** | ✅ PASS | 复用 OS-neutral 协议不分叉 wire；端到端以参考键盘 + 第二台电脑验收（quickstart）；固件在 `zmk-keybeacon` 平级仓库，本仓库不改固件。 |
| **Testing & Verification Discipline** | ✅ PASS | 解析/派生为纯函数、无需 BLE 硬件即可测（FR-014）；quickstart 提供 Given/When/Then 并映射 FR/SC；降级/兼容路径有可执行验证（负测矩阵）。 |
| **Governance** | ✅ PASS | 本 plan 即 Constitution Check；提交触达 `protocol/**`、`conformance/**`、`app/*/Sources/**` 需附本 Check；`/speckit-analyze` 需 CRITICAL=0、HIGH=0。 |

**Verdict**: 6 原则 + 3 过程 gate 全部 PASS，无 Complexity Tracking 需求。

## Project Structure

### Documentation (this feature)

```text
specs/005-host-link-profile-awareness/
├── spec.md              # /speckit-specify 输出
├── plan.md              # 本文件
├── research.md          # Phase 0：技术决策（方案 A）+ 两端落点 + 风险
├── data-model.md        # Phase 1：AA4 特征、LinkSlot 实体、五态派生
├── quickstart.md        # Phase 1：构建/测试 + Given/When/Then + 负测矩阵
├── contracts/
│   ├── host-link-context.md   # AA4 wire 增量契约（HW/P-L/C-L，C13/C14）
│   └── consumer-flow.md       # 两端同构消费流程与派生契约
├── checklists/
│   └── requirements.md  # spec 质量清单
└── tasks.md             # Phase 2 输出（/speckit-tasks，本命令不创建）
```

### Source Code (repository root)

```text
protocol/                                  # [MODIFIED] 唯一真相源，本 feature 发布 1.2 MINOR
├── README.md                              # §14 新增 AA4 特征（只读）、§14.5 发现、§13、§11（英中双语）
├── CHANGELOG.md                           # 1.2.0 条目（英中双语）
└── VERSION                                # 1.1.0 → 1.2.0

conformance/                               # [MODIFIED] 共享测试向量
├── conformance_tool.py                    # 新增 parse_link_slot + AA4 属性/长度校验
├── checklist.md                           # 增 C13/C14（英中双语）
└── tests/                                 # 新增 link_slot 解析向量

app/macos/                                 # [MODIFIED] CoreBluetooth/AppKit 消费者
├── Sources/BleWidgetCore/
│   ├── LinkSlot.swift                      # [NEW] AA4 单字节解析（纯函数）
│   └── LocalHostStatus.swift               # [NEW] 五态枚举 + deriveLocalHostStatus（纯函数）
│   # ConnectivityStatus.swift / CapabilityMatrix.swift 不改
├── Sources/BleWidget/
│   ├── BLEClient.swift                     # [MODIFIED] AA4 常量/发现/读 + readLinkSlot()（无需 pendingRead）
│   ├── FloatingPanel.swift                 # [MODIFIED] renderHostRow 五态分支
│   ├── Localization.swift                  # [MODIFIED] 5 个 key（英/中）
│   └── DiagnosticsLogger.swift             # [MODIFIED] hostlink.* 诊断
└── Tests/BleWidgetTests/
    └── HostLinkProfileAwarenessTests.swift # [NEW] LinkSlot + 五态穷举

app/windows/                               # [MODIFIED] WinRT/WPF 消费者
├── src/KeyBeacon.Core/
│   ├── LinkSlot.cs                          # [NEW] AA4 单字节解析
│   └── HostContextStatus.cs                 # [NEW] 五态 + DeriveLocalHostStatus（纯函数）
│   # ConnectivityStatus.cs / CapabilityMatrix.cs 不改；KbpUuids.cs 加 AA4 常量
├── src/KeyBeacon.App/
│   ├── Ble/KeyboardMonitor.cs               # [MODIFIED] AA4 发现 + 复用 ReadAsync 读/重读；快照携带 host context
│   ├── Ui/MainViewModel.cs                   # [MODIFIED] 五态渲染分支
│   ├── Localization/Resources*.resx          # [MODIFIED] 5 key（en + zh-CN）
│   └── Diagnostics/DiagnosticsLogger.cs       # [MODIFIED] hostlink.* 事件常量
└── tests/KeyBeacon.Core.Tests/
    └── HostContextStatusTests.cs             # [NEW] LinkSlot + 五态穷举

# 兄弟仓库（不在本仓库改动）：zmk-keybeacon —— 固件实现 AA4 只读特征（per-link slot 生产者）
```

**Structure Decision**: 严格遵循宪法 Principle I「两端都是消费者、协议是唯一真相源」。方案 A 把 per-link slot 做成**独立只读特征 AA4**，带来三点结构收益：(1) **既有解析器零改动**（`ConnectivityStatus`/`CapabilityMatrix` 两端均不动），新增仅 `LinkSlot` + `LocalHostStatus`/`HostContextStatus` 两个纯类型；(2) **两端对称**——都不需要区分 READ/NOTIFY 帧（macOS 省掉最脆弱的 `pendingRead` 标志，Windows `ReadAsync` 本就天然区分）；(3) 能力探测复用既有「按特征存在性判定」路径。固件生产者留在 `zmk-keybeacon` 跨仓库协作，本仓库不触碰。

## Complexity Tracking

> Constitution Check 无 gate 违规，本节为空。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| —         | —          | —                                    |
