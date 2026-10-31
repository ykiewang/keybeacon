# Implementation Plan: Windows 桌面客户端（KeyBeacon Windows Client）

**Branch**: `003-windows-desktop-client` | **Date**: 2026-10-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/003-windows-desktop-client/spec.md`

## Summary

为 KeyBeacon 增加 Windows 桌面客户端，对标 macOS 版的完整能力：通过系统托盘 + 常驻置顶悬浮窗，实时显示已连接 KBP 键盘的当前层、修饰键，以及 KBP 1.1 的连接与电量。技术路线为**协议共享、各平台原生实现**：复用 `protocol/`（线上契约唯一真相源）与 `conformance/`（跨平台测试向量），用 C#/.NET 原生重实现约数百行解析逻辑，经同一套测试向量验证——不引入跨语言 core/FFI。

因 "WinRT 能否枚举已连接且不广播的 HID 键盘并订阅 GATT 通知" 尚未在真实硬件上验证，本计划设 **Phase 0 可行性 probe** 作为实现前的硬门禁：probe 通过才推进完整客户端实现。Linux 列为尽力而为、不阻塞 Windows（本 feature 仅做 Linux 可行性复用现有 Python 工具的探查，不交付 Linux GUI）。

## Technical Context

**Language/Version**: C# 12 / .NET 8（LTS）

**Primary Dependencies**:
- UI/托盘/悬浮窗：WPF（`net8.0-windows10.0.19041.0`）+ 托盘图标库（`H.NotifyIcon.Wpf` 或等价）
- BLE：WinRT 投影（`Windows.Devices.Bluetooth*`，经 `net8.0-windows10.0.19041.0` TFM 自动提供，无需打包为 MSIX/UWP）
- 日志：`Microsoft.Extensions.Logging` 抽象 + 滚动文件接收器（如 Serilog rolling file）
- 诊断包打包：`System.IO.Compression`
- 本地化：.NET `.resx` 资源 + `CultureInfo`（跟随系统区域）

**Storage**: 本地文件——用户设置（选定键盘、显示模式、钉角、日志详细程度）+ 滚动诊断日志文件（`%LOCALAPPDATA%\KeyBeacon\`）。无数据库。

**Testing**: xUnit。纯解析逻辑（`KeyBeacon.Core`）以 `conformance/` 现有测试向量（81 pytest 用例覆盖的同一批 payload 布局）验证，**无需蓝牙硬件**。BLE/UI 层通过 quickstart 手工剧本 + Phase 0 probe 真机验收。

**Target Platform**: Windows 10 version 2004（build 19041）及以上 + Windows 11，x64 与 ARM64。

**Project Type**: 桌面应用（desktop-app），独立于现有 `app/macos/` Swift 工程。

**Performance Goals**: 层/修饰键变化后显示在 3 秒内更新（SC-002）；断开后 3 秒内切换为未连接（SC-003）；空闲时零多余刷新（与 KBP "未变化不通知" 一致）。

**Constraints**:
- 不改动 KBP 线上契约（仅新增一个消费者，双向兼容，FR-012）。
- WinRT async 必须在 MTA 线程模型下运行（否则挂起，Phase 0 风险之一）。
- 未打包（非 MSIX）运行；首启体验对标 macOS 的 ad-hoc 分发现状。
- 诊断信息避免泄露非必要 PII（FR-025）。

**Scale/Scope**: 单用户桌面应用；新增约 C# 源码规模预估：`KeyBeacon.Core` ~550 行（解析器移植）、`KeyBeacon.App` ~1500–2000 行（BLE + 托盘 + 悬浮窗 + 诊断 + 本地化）、`KeyBeacon.Core.Tests` ~400 行、`KeyBeacon.Probe` ~200 行（Phase 0）。

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

依据 `.specify/memory/constitution.md v1.1.0`（6 原则 + Platform Scope & Delivery + Testing & Verification Discipline + Governance）逐条评估。

| 原则 | 结论 | 证据 |
|------|------|------|
| **I. Wire-Contract Self-Containment** | ✅ PASS | 本 feature 是**消费者**；全部 wire 行为读自 `protocol/README.md §1/§4/§14`，不发明任何新字段。Windows 代码位于 `app/windows/`，不侵入 `protocol/`。C# 解析器逐字节复刻协议偏移。 |
| **II. Backward Compatibility is Non-Negotiable** | ✅ PASS | 仅新增消费者，零 wire 改动（FR-012）。service UUID 不变。新 app 遇老固件 → 按能力位隐藏 1.1 字段（FR-016）。现有 macOS app / 固件行为不受影响（SC-004）。 |
| **III. Identity From Protocol, Not Branding** | ✅ PASS | FR-002 仅以 service UUID 判兼容，无型号白名单/vendor 匹配；展示名取自 GAP 名（FR-003）。 |
| **IV. Observable Degradation Over Guessing** | ✅ PASS | FR-007 断开即全字段陈旧；**FR-007a 连接内陈旧=最后已知值+时间戳+弱化**（与宪法原句一致）；FR-016/017 诚实隐藏/哨兵；FR-018 每个降级事件恰好一条结构化日志；FR-022~025 在此之上提供完整日志收集。3 秒陈旧（SC-003）。 |
| **V. Spec-First Development (NON-NEGOTIABLE)** | ✅ PASS | 本 feature 正走 specify → clarify → plan → tasks 流程；contracts 为 drafting ground，protocol/ 为 published 真相源。 |
| **VI. Bilingual Normative Docs** | ✅ PASS（含约束） | spec/plan/contracts 为仓库内部文档，不在 VI 强制范围。**约束**：若本 feature 最终改动根 `README.md` 或新增任何**规范性公开文档**（如面向键盘作者的 Windows 使用说明），MUST 英中双语。FR-021 的 UI 中英双语与此精神一致（属本地化，非文档）。 |
| **Platform Scope & Delivery** | ✅ PASS | 新增 Windows 主机，复用 OS-neutral 协议、不分叉 wire；端到端以参考键盘（Corne）验收；ZMK 固件不受影响。Linux 显式列为尽力而为（FR-015）。 |
| **Testing & Verification Discipline** | ✅ PASS | `KeyBeacon.Core` 新增公共类型全部配 xUnit；解析逻辑为纯函数、无需 BLE 硬件即可测（SC-005）；quickstart 提供 Given/When/Then；至少一条剧本以参考键盘复现；本 feature 不触碰 `app/macos/`，故 macOS 回归为零（SC-004）。 |
| **Governance** | ✅ PASS | 本 plan 即 Constitution Check 产物；后续 `/speckit-analyze` 要求 CRITICAL=0、HIGH=0 方可合并。 |

**Verdict**: 6 原则 + 3 过程 gate 全部 PASS，无需 Complexity Tracking。

## Project Structure

### Documentation (this feature)

```text
specs/003-windows-desktop-client/
├── spec.md              # /speckit-specify + /speckit-clarify 输出
├── plan.md              # 本文件
├── research.md          # Phase 0 输出：技术决策 + probe 验证方案与 FAIL 回退
├── data-model.md        # Phase 1 输出：实体与字段
├── quickstart.md        # Phase 1 输出：Windows 构建/运行 + 端到端验收剧本
├── contracts/           # Phase 1 输出
│   ├── ble-consumption.md     # WinRT 消费者流程契约（引用 protocol/，不复制）
│   ├── diagnostics-bundle.md  # 诊断包内容与脱敏契约
│   └── probe-cli.md           # Phase 0 probe CLI 契约（参数/输出/退出码）
├── checklists/
│   └── requirements.md  # spec 质量清单（已完成）
└── tasks.md             # Phase 2 输出（/speckit-tasks，本命令不创建）
```

### Source Code (repository root)

```text
app/windows/                              # [NEW] 与 app/macos/ 平级的 Windows 工程
├── KeyBeacon.sln
├── src/
│   ├── KeyBeacon.Core/                   # net8.0（纯逻辑，跨平台可测，无平台依赖）
│   │   ├── KbpUuids.cs                   # 服务/特征 UUID + 家族判定 + Classify（supported/unsupportedVersion/notAKeyboard）
│   │   ├── KeyboardStatus.cs             # KBP 1.0 层+修饰键解析（移植自 Swift）
│   │   ├── CapabilityMatrix.cs           # KBP 1.1 能力位
│   │   ├── ConnectivityStatus.cs         # KBP 1.1 连接特征解析
│   │   ├── BatteryStatus.cs              # KBP 1.1 电量特征解析
│   │   ├── StalenessTracker.cs           # 3 秒陈旧判定
│   │   └── CompatibleKeyboard.cs         # 设备视图 + 选择解析
│   └── KeyBeacon.App/                    # net8.0-windows10.0.19041.0（WPF + WinRT BLE）
│       ├── Ble/                          # WinRT 枚举/连接/发现/订阅
│       ├── Ui/                           # 托盘图标 + 菜单 + 常驻置顶悬浮窗
│       ├── Diagnostics/                  # 结构化日志 + 滚动文件 + 诊断包导出
│       ├── Localization/                 # .resx（zh-CN / en），跟随系统区域
│       └── Settings/                     # 选定键盘/显示模式/钉角/日志级别
├── tests/
│   └── KeyBeacon.Core.Tests/             # net8.0 xUnit：解析器测试向量
└── tools/
    └── KeyBeacon.Probe/                  # net8.0-windows（Phase 0 可行性 CLI）

protocol/        # [UNCHANGED] 唯一真相源
conformance/     # [UNCHANGED] 共享测试向量；Linux 可行性复用 conformance_tool.py
app/macos/       # [UNCHANGED] 本 feature 不触碰（保证 macOS 零回归）
```

**Structure Decision**: 采用与 `app/macos/`（`BleWidgetCore` 纯逻辑 + `BleWidget` 平台层）同构的分层——`KeyBeacon.Core`（`net8.0`，纯解析，跨平台可测）+ `KeyBeacon.App`（`net8.0-windows`，WinRT/WPF 平台层）。这把 519 行协议解析与平台 BLE/UI 清晰隔离：解析器用共享测试向量验证、无需 Windows 即可跑；仅 BLE/UI/诊断需 Windows 环境。Phase 0 的 `KeyBeacon.Probe` 复用 `KeyBeacon.Core`，其 BLE 封装即正式客户端的地基。

## Complexity Tracking

> Constitution Check 无 gate 违规，本节为空。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| —         | —          | —                                    |
