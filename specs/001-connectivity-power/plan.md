# Implementation Plan: 连接与电量指标(Roadmap A)

**Branch**: `001-connectivity-power` | **Date**: 2026-10-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-connectivity-power/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

把 Roadmap A「连接与电量」整组指标以 **KBP 1.1 MINOR 增量** 形式落地,打通 **协议 →
一致性套件 → macOS 应用** 三层:

- 协议层:在既有 KBP service UUID(`AA440AA0-…`)下**新增 2 个可选特征**——`Connectivity`
  特征承载所有状态性字段(能力位、主机连接、profile、分体在/离线、输出端点、充电);
  `Battery` 特征承载数值性字段(整机或左右半电量百分比)。能力位中显式包含 `is_split`,
  由固件按编译期事实(如 ZMK 的 `CONFOG_ZMK_SPLIT`)声明。KBP 1.0 的 `AA440AA1-…` 特征
  保持零改动。
- 一致性套件:把 Python 自测工具**跨平台化**(macOS/Linux/Windows,改用 `bleak` BLE 库),
  新增 A 组逐字段检查项;原 PyObjC 版本保留为 `conformance_tool_macos.py` 作为 fallback。
- macOS app:在 `BleWidgetCore` 下新增 4 个核心模型(`CapabilityMatrix`、
  `ConnectivityStatus`、`BatteryStatus`、`StalenessTracker`),在 `BLEClient` 中追加对两个
  新特征的发现与订阅,在悬浮面板增加一张「连接与电量」卡片;对老固件(未暴露 1.1 特征)
  完全隐藏新卡片以保持 KBP 1.0 行为。

## Technical Context

**Language/Version**:
- 协议规范:语言无关(规范为 BLE GATT wire contract)
- macOS 应用:Swift 5.9+(target macOS 12+),沿用现有 `app/macos/Package.swift`
- 一致性 CLI:Python 3.9+(`bleak>=0.21` 要求 Python 3.9+)

**Primary Dependencies**:
- macOS 应用:`CoreBluetooth`、`AppKit`(均系统框架,无外部依赖)
- 一致性 CLI:`bleak`(跨平台 BLE 库,封装 CoreBluetooth / BlueZ / WinRT),保留 `pyobjc-framework-CoreBluetooth` 仅给 macOS legacy 工具用
- 协议文档:无外部依赖

**Storage**:
- `AppSettings`(基于 `UserDefaults`)继续承载"选中键盘的 identifier";本 feature **不新增**持久化字段
- 诊断日志通过现有 `os.Logger`(macOS)输出,**不新增** 文件级存储

**Testing**:
- macOS 应用:XCTest(沿用 `Tests/BleWidgetTests`),新增 4 个测试文件(每新模型 1 个)
- 一致性 CLI:pytest(可选,主要是**行为级手工自测清单** + 自测工具自身的 exit code 契约)
- 协议规范:无直接自动测试,通过一致性套件间接验证

**Target Platform**:
- macOS 应用:macOS 12+
- 一致性 CLI:macOS 12+、Ubuntu 20.04+、Windows 10+(bleak 支持)
- 协议规范:与 OS 无关

**Project Type**:多组件单仓(protocol + conformance + macOS app),对应 Project Structure 中的自定义结构(非模板的 Option 1/2/3 任一)。

**Performance Goals**:
- 状态变化到 UI 更新:P95 ≤ 2s / P50 ≤ 1s(SC-002)
- 电量显示偏差:≤ 5 个百分点(SC-003)
- 一致性 CLI 一轮运行:≤ 60s(SC-005)
- BLE 带宽:数值性字段(电量)节流至 ≥ 1 pp 变化或 ≥ 1s 间隔(FR-008),避免打字时占用带宽

**Constraints**:
- 向后兼容 KBP 1.0:service UUID 不变,`AA440AA1-…` 特征语义零改动,老 app 在新固件上继续工作、新 app 在老固件上隐藏新 UI(SC-004)
- 字段级能力探测:app 对缺失字段必须隐藏而非占位(FR-013、SC-006)
- 陈旧值 3 秒阈值:单字段 3 秒无 notify 即标灰 + 时间戳(FR-015)
- 代码风格:遵循 `app/macos/Sources/BleWidgetCore` 现有命名(PascalCase 文件 / public API 显式 `public`)

**Scale/Scope**:
- 协议文档:新增 1 节(§14「KBP 1.1 Connectivity & Power 可选特征」)+ 英中双语
- 一致性清单:新增 6 条 A 组检查项(C7–C12)
- macOS 代码:新增约 400 行 Swift,修改 BLEClient ~150 行
- 一致性 CLI:新增约 500 行 Python(bleak 版主体)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Phase-0(本节首次写入时)

当时仓库 `.specify/memory/constitution.md` 全文为模板占位符(未实例化任何 Principle、
Section、Governance 规则),因此**自动通过** Constitution Check,设计以 KBP 1.0 既有
工程风格为代理 principle(向后兼容、wire self-contained、身份只来自 UUID、snapshot
未变不发)。

### Post-Phase-1 + Post-Ratification(本节重做,针对 constitution v1.0.0)

本 plan 的 Phase 0/1 设计与**已 ratify 的** `.specify/memory/constitution.md` v1.0.0
的 6 条 Principle 逐条对表:

| Principle | 对表结论 | 证据 |
|-----------|---------|------|
| **I. Wire-Contract Self-Containment** | ✅ 符合 | `contracts/protocol-kbp11.md` 为字节级自洽契约,不引用 `app/`/`conformance/`;§8 ZMK 映射已标注"非规范性";实施阶段 T004 把本 contract 1:1 搬进 `protocol/README.md §14`,保持 "protocol/ = 单一真相源" |
| **II. Backward Compatibility is Non-Negotiable** | ✅ 符合 | KBP 1.1 = MINOR,service UUID `AA440AA0-…` 零改动,`AA440AA1-…` payload 零改动(§research.md §1 Decision);SC-004 要求两向兼容崩溃率 = 0;T042 作为硬性剧本 F 验证 |
| **III. Identity From Protocol, Not Branding** | ✅ 符合 | 本 feature 不新增任何型号识别/白名单/vendor 匹配器;`KBPCompatibility.swift` 现有 UUID 分类器未变;新增字段纯粹从 BLE wire 读 |
| **IV. Observable Degradation Over Guessing** | ✅ 符合 | 三级能力探测(service UUID → characteristic 存在性 → capability bits)在 `data-model.md §9 IV-X5` 固化;字段 bit = 0 时 UI MUST 完全不占位(`contracts/macos-ui.md §1.2 U-1`);3 秒 stale + 断连立即降级(`StalenessTracker` + T017/T018);**FR-014 已改写为"不主动 polling"**,与"honest nothing-to-show"原则强对齐;诊断日志覆盖所有 degradation 事件(T020 + T047) |
| **V. Spec-First Development (NON-NEGOTIABLE)** | ✅ 符合 | 已完成 /speckit-specify + /speckit-clarify(两轮,共 7 条)+ /speckit-plan + /speckit-tasks + 两轮 /speckit-analyze;所有 contracts 为"drafting ground",protocol/README 为"published artifact"(T004 把 contract 搬进去),完全符合 Principle V 的"contract-first,published-second"流程 |
| **VI. Bilingual Normative Docs** | ✅ 符合(实施阶段强制) | 本 plan Project Structure 的 `protocol/README.md` / `protocol/CHANGELOG.md` / `conformance/CONFORMANCE.md` / `conformance/checklist.md` / 根 `README.md` 均要求英中双语(T004–T008);T046 为最终 sweep,验证规范语(MUST→必须 / SHOULD→应 / MAY→可)稳定渲染;contracts/ 下的 markdown 为仓库内部文档(非 normative public artifact),按惯例以中文为主,不受 Principle VI 约束 |

**Testing & Verification Discipline**:
- `BleWidgetCore` 新增 4 个 public 类型(CapabilityMatrix / ConnectivityStatus / BatteryStatus / StalenessTracker)**全部**有对应 XCTest(T012/T014/T016/T018),满足"A new public type in `BleWidgetCore` without matching XCTest MUST fail code review"。
- Payload 解析逻辑(`parse_connectivity` / `parse_battery`)为纯函数,T010 + T026 + T032 覆盖 pytest 单测,满足"MUST be covered by pure-function unit tests runnable without BLE hardware"。
- 每个 US 的最后一个任务 (T027/T033/T037/T040) 执行 `quickstart.md` 的 Given/When/Then 剧本,满足"Every feature MUST ship a `specs/NNN/quickstart.md` with explicit Given/When/Then scenarios"。
- 参考键盘 Totem 的要求在 §1.1 显式标注,满足"At least one scenario per feature MUST be reproducible with the reference keyboard"。

**Compliance Review**:
- 本 plan + feature 下的任何涉及 `protocol/` / `conformance/` / `app/*/Sources/` / `specs/*/contracts/` 的 commit 都需要在 PR 描述中给出显式 Constitution Check(本节即示范)。
- `/speckit-analyze` 第二轮(本次 commit 后再做一次)应得到 CRITICAL = 0、HIGH = 0。


## Project Structure

### Documentation (this feature)

```text
specs/001-connectivity-power/
├── spec.md                          # 需求规范(已完成,含 Clarifications)
├── plan.md                          # 本文件(/speckit-plan 输出)
├── research.md                      # Phase 0 输出:技术决策与依据
├── data-model.md                    # Phase 1 输出:实体与字段
├── quickstart.md                    # Phase 1 输出:端到端验证指南
├── contracts/
│   ├── protocol-kbp11.md            # KBP 1.1 wire 契约(新特征 + payload)
│   ├── conformance-cli.md           # 一致性 CLI 契约(exit code + 支持矩阵输出)
│   └── macos-ui.md                  # macOS 面板「连接与电量」卡片契约
├── checklists/
│   └── requirements.md              # 已完成的规范质量 checklist
└── tasks.md                         # Phase 2 输出(由 /speckit-tasks 生成,本命令不创建)
```

### Source Code (repository root)

```text
protocol/
├── README.md                        # [MODIFIED] 新增 §14 KBP 1.1 可选特征(英中)
├── CHANGELOG.md                     # [MODIFIED] 新增 1.1.0 条目(英中)
└── VERSION                          # [MODIFIED] 1.0.0 → 1.1.0

conformance/
├── CONFORMANCE.md                   # [MODIFIED] 新增 A 组字段构建指引(英中)
├── checklist.md                     # [MODIFIED] 新增 C7–C12 条目(英中)
├── conformance_tool.py              # [REWRITTEN] 跨平台(bleak 后端),覆盖 1.0 + 1.1
└── conformance_tool_macos.py        # [NEW,从原文件备份] 原 PyObjC 工具,保留为 macOS legacy

app/macos/
├── Package.swift                    # [UNCHANGED] 无新 target
├── Sources/BleWidgetCore/
│   ├── AppSettings.swift            # [UNCHANGED]
│   ├── BLEClient.swift              # [MODIFIED] 发现 + 订阅两个新特征,新增 delegate 回调
│   ├── CompatibleKeyboard.swift     # [UNCHANGED]
│   ├── KBPCompatibility.swift       # [UNCHANGED]  service UUID 不变
│   ├── KeyboardStatus.swift         # [UNCHANGED]  KBP 1.0 payload
│   ├── CapabilityMatrix.swift       # [NEW]  能力位解析 + is_split 等
│   ├── ConnectivityStatus.swift     # [NEW]  Connectivity 特征 payload 解析
│   ├── BatteryStatus.swift          # [NEW]  Battery 特征 payload 解析
│   └── StalenessTracker.swift       # [NEW]  3 秒陈旧判定(FR-015)
├── Sources/BleWidget/
│   ├── AppDelegate.swift            # [MODIFIED] 诊断日志钩子(FR-018)
│   ├── FloatingPanel.swift          # [MODIFIED] 新增「连接与电量」卡片
│   └── main.swift                   # [UNCHANGED]
└── Tests/BleWidgetTests/
    ├── CompatibilityTests.swift     # [UNCHANGED]
    ├── KeyboardIdentityTests.swift  # [UNCHANGED]
    ├── KeyboardStatusTests.swift    # [UNCHANGED]
    ├── MigrationTests.swift         # [UNCHANGED]
    ├── CapabilityMatrixTests.swift  # [NEW]
    ├── ConnectivityStatusTests.swift# [NEW]
    ├── BatteryStatusTests.swift     # [NEW]
    └── StalenessTrackerTests.swift  # [NEW]
```

**Structure Decision**:非模板任一标准布局。本仓库是「协议 + 一致性 + macOS 参考主机」
三合一仓库,各组件边界清晰但在同一仓库版本演进。plan 中的改动按**各组件物理目录对齐**,
避免跨目录的共享源文件。协议改动不侵入 app/conformance,反之亦然——保持 KBP
`protocol/README.md` 开篇的"self-contained"承诺。

## Complexity Tracking

> Constitution Check 无 gate violation,本节保留为空。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| —         | —          | —                                   |
