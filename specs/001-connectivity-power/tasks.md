---

description: "Task list for 连接与电量指标 (Roadmap A — KBP 1.1)"
---

# Tasks: 连接与电量指标(Roadmap A — KBP 1.1)

**Input**: Design documents from `/specs/001-connectivity-power/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/{protocol-kbp11,conformance-cli,macos-ui}.md, quickstart.md

**Tests**: 本 feature **包含测试任务**。plan.md 的 Testing 节与 constitution.md 的 Testing & Verification Discipline(Principle VI 的相邻章)明确要求:
- `BleWidgetCore` 新增类型 MUST 有对应的 XCTest 覆盖
- `conformance_tool.py` 的 payload 解析 MUST 有 pytest 单测
- quickstart.md 的手工剧本 MUST 作为 FR/SC 验证入口

**Organization**: 按 User Story 分组;US1 (P1) 作为 MVP 切片。

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: 不同文件、无依赖冲突,可并行
- **[Story]**: 该任务归属哪个 user story(US1/US2/US3/US4)
- 文件路径必须明确,所有路径相对仓库根

## Path Conventions

本仓库是**协议 + 一致性 + macOS 参考主机**三合一结构:

- `protocol/` — BLE wire 契约(KBP 1.0 已存在;本次新增 1.1 §14)
- `conformance/` — 一致性套件(Python)
- `app/macos/` — macOS 应用(Swift Package)

无标准 `src/` + `tests/` 根布局,所有路径按三组件物理目录对齐。

---

## Phase 1: Setup(共享基础设施)

**Purpose**: 协议版本号升档、PyObjC 工具备份、Python 依赖声明。

- [ ] T001 备份原 PyObjC 工具为 macOS legacy:`git mv conformance/conformance_tool.py conformance/conformance_tool_macos.py`,并在 `conformance/conformance_tool_macos.py` 文件顶部注释说明"legacy — KBP 1.0 only, macOS-only; see conformance_tool.py for cross-platform tool"。
- [ ] T002 [P] 新建 `conformance/requirements.txt`,声明依赖:`bleak>=0.21`(主工具)、`pyobjc-framework-CoreBluetooth>=9.0; sys_platform == "darwin"`(legacy 工具)、`pytest>=7.0`(单测)。
- [ ] T003 [P] 修改 `protocol/VERSION` 从 `1.0.0` 到 `1.1.0`(单行文件,整行替换)。

**Checkpoint**: 旧工具已备份,协议版本号已 bump;新工具与新代码可以开始落地。

---

## Phase 2: Foundational(所有 US 的阻塞前置)

**Purpose**: 协议文档英中双语化、一致性 CLI 骨架、字段级能力解析框架、BLE 发现与订阅链路。本阶段完成后,四个 user story 可独立开展实现与验收。

**⚠️ CRITICAL**: 本阶段未完成,任何 user story 的实现都不能开始(全部依赖 CapabilityMatrix / ConnectivityStatus / BLEClient 的新订阅路径)。

### 协议文档(双语,Constitution Principle VI)

- [ ] T004 [P] 在 `protocol/README.md` 追加 §14 "KBP 1.1 Connectivity & Power(可选特征)",**英中双语** side-by-side。内容逐字对齐 `specs/001-connectivity-power/contracts/protocol-kbp11.md` §1–§7:新增 2 个 characteristic UUID、Connectivity payload 布局(7+ 字节)、Battery payload 布局(1 或 2 字节)、capability bits 位分配、生产者/消费者 MUST 规则、节流规则(状态性 vs 数值性)、一致性清单扩展指引。规范语(MUST/SHOULD/MAY)在中文镜像中保留稳定渲染 (MUST → 必须 / SHOULD → 应 / MAY → 可)。
- [ ] T005 [P] 在 `protocol/CHANGELOG.md` 顶部追加 `## [1.1.0] - 2026-XX-XX` 条目,**英中双语**,内容:Added(新增 Connectivity + Battery characteristic、capability bits、`is_split` 位、staleness 消费规则)、Changed(无 wire 破坏;service UUID 与 `AA440AA1-…` payload 保持零改动)、Deprecated(无)、Migration(KBP 1.0 固件 ↔ KBP 1.1 app 的双向兼容矩阵引用 research.md §11)。
- [ ] T006 [P] 修改仓库根 `README.md` 的 Roadmap A 节:标注"实施中(KBP 1.1 feature `001-connectivity-power`)",**英中双语**;插入链接到 `specs/001-connectivity-power/spec.md` 与 `protocol/README.md §14`。

### 一致性套件(双语文档 + 跨平台骨架)

- [ ] T007 [P] 在 `conformance/checklist.md` 追加 C7–C12 一致性条目,**英中双语**。逐字对齐 `specs/001-connectivity-power/contracts/protocol-kbp11.md §7` 与 `contracts/conformance-cli.md §5`:C7 `AA440AA2-…` 特征存在性 + READ+NOTIFY+CCC(REQUIRED if present);C8 Connectivity READ ≥ 7 字节 + P-C1..P-C4 不变量(REQUIRED if present);C9 `AA440AA3-…` 特征存在性 + payload 长度与 is_split 一致(REQUIRED if present);C10 状态字段变化触发 notify + snapshot 抑制(REQUIRED if present);C11 数值字段节流符合 ≥ 1 pp **或** ≥ 1 s(RECOMMENDED if present);C12 1.1 特征仅在分体 central 暴露(REQUIRED split, MANUAL)。
- [ ] T008 [P] 修改 `conformance/CONFORMANCE.md`,**英中双语** 追加一节 "A-group fields (KBP 1.1)",内容:字段 → characteristic 映射表、capability bits 位含义、固件实现者路线图(ZMK 事件 API 引用 research.md §9)、legacy macOS 工具与跨平台工具的分工说明。
- [ ] T009 新建 `conformance/conformance_tool.py`(**全新文件**,跨平台 bleak 实现)。按 `specs/001-connectivity-power/contracts/conformance-cli.md` 的全部 §1-§6:
  - §1 命令行参数:`--timeout`(default 15)/ `--observe`(default 10)/ `--json` / `--device-filter` / `--no-color` / `-h`
  - §2 exit code 契约:0 PASS,1 REQUIRED FAIL,2 环境错误(`BleakError` / 蓝牙关闭 / 缺依赖)
  - §3 人类可读输出:每行 `C<n>  [PASS|FAIL|WARN|SKIP|MANUAL]  <description>` 格式
  - §4 `--json` 支持矩阵 schema(spec_version `kbp-conformance-cli/1`、顶层 keys 稳定排序、J-1..J-4 不变量)
  - §5 C1–C6 从 legacy 工具的检查逻辑复用(通过 bleak 等价 API 实现,不 import PyObjC)
  - §6 BLE 后端:`bleak>=0.21`,`BleakScanner.discover()` + 已连接外设枚举;payload 解析封装为纯函数 `parse_connectivity(bytes)->dict` / `parse_battery(bytes, is_split)->dict`
  - 此 task **不**实现 C7–C12 字段级检查,只搭骨架 + 跳过(all SKIP + reason "C7-C12 implemented in user story phases");C7-C12 的具体检查落在各 US phase 的任务中
- [ ] T010 [P] 新建 `conformance/tests/test_payload_parsing.py`(pytest),覆盖 `parse_connectivity` 与 `parse_battery` 的纯函数单测:happy path、短 payload < 7 字节(应返回 `None` + 错误码)、长 payload > 7 字节(应忽略尾部)、保留位非零(应忽略)。此文件只覆盖 Foundational 的解析逻辑,不覆盖字段语义(字段语义测试在 US phase)。

### macOS core 模型(字段级解析 + staleness)

- [ ] T011 [P] 新建 `app/macos/Sources/BleWidgetCore/CapabilityMatrix.swift`(public struct),按 `specs/001-connectivity-power/data-model.md` §1 字段表:`isSplit`、`hasHostConnection`、`hasProfile`、`hasSplitLink`、`hasOutputEndpoint`、`hasLeftCharging`、`hasRightCharging`、`_reserved7`(8 个 Bool)。public init 从 `UInt8` 解析;public computed property `isConsistent: Bool`(实现 IV-C1 的 `hasSplitLink → isSplit` **以及** IV-C3 的 `hasRightCharging → (isSplit ∧ hasLeftCharging)`,false 时记诊断日志调用点由 BLEClient 承担)。遵循 `BleWidgetCore` 现有命名(PascalCase 文件 / public API 显式 `public`)。
- [ ] T012 [P] 新建 `app/macos/Tests/BleWidgetTests/CapabilityMatrixTests.swift`(XCTest),覆盖:
  - 全 0 字节 → 所有 flag false
  - 全 1 字节 → 所有 flag true(含 `_reserved7`)
  - 单 bit 组合(2^7 = 128 组,用 parametrized loop)
  - IV-C1:`hasSplitLink=1 && isSplit=0` → `isConsistent == false`
  - IV-C2:`_reserved7=1` 不触发任何 assertion failure
  - IV-C3:`hasRightCharging=1 && isSplit=0` → `isConsistent == false`;`hasRightCharging=1 && hasLeftCharging=0` → `isConsistent == false`;`isSplit=1 && hasLeftCharging=1 && hasRightCharging=1` → `isConsistent == true`
- [ ] T013 新建 `app/macos/Sources/BleWidgetCore/ConnectivityStatus.swift`(public struct)。按 `data-model.md` §2/§3/§6/§7 的字段表,包含:`capability: CapabilityMatrix`、`link: KeyboardLink`(嵌套 struct,含 `connected: Bool`、`lastDisconnectReason: enum {unknown, explicit, timeout}`)、`profile: BLEProfileSlots`(嵌套 struct,含 `index: UInt8`、`isOpen: Bool`、`maxSlots: UInt8`)、`splitFlags: (leftOnline: Bool, rightOnline: Bool)`、`output: OutputEndpoint`(enum `{unknown, usb, ble, reserved(UInt8)}`)、`chargingFlags: (leftCharging: Bool, rightCharging: Bool)`。public static `parse(from data: Data) -> ConnectivityStatus?`:数据 < 7 字节返回 nil(IV-CS1);≥ 7 字节解析前 7 字节、忽略尾部(IV-CS2)。依赖 T011。
- [ ] T014 [P] 新建 `app/macos/Tests/BleWidgetTests/ConnectivityStatusTests.swift`(XCTest),覆盖**所有字段**的解析(US1/2/3/4 的字段都在同一 payload 内一次性 decode,测试在此文件集中):
  - IV-CS1:6 字节 payload → `parse` 返回 nil
  - IV-CS2:12 字节 payload → 解析成功,忽略尾部 5 字节
  - IV-K1:全字段的边界值(host_state bit 0/1 组合、disconnect reason 00/01/10/11)
  - IV-P1:`profile_index > profile_max_slots`(越界)→ 解析成功但由 BLEClient 负责钳制(此单测验证 parse 不丢数据)
  - IV-O2:`output_endpoint` 保留值 3..255 → 映射到 `.reserved(UInt8)`
  - splitFlags / chargingFlags 的 bit 0 / bit 1 独立正确性
- [ ] T015 [P] 新建 `app/macos/Sources/BleWidgetCore/BatteryStatus.swift`(public struct)。按 `data-model.md` §5/§8:
  - public enum `BatteryReading` = `.percent(UInt8)` | `.unavailable`;其中 UInt8 constraint = `0..=100`,`255` → `.unavailable`,`101..=254` → `.unavailable` + outOfRange 标记
  - public enum `Kind` = `.overall(BatteryReading)` | `.split(left: BatteryReading, right: BatteryReading)`
  - public static `parse(from data: Data, isSplit: Bool) -> BatteryStatus?`:isSplit=false 要求 1 字节(IV-BS1),isSplit=true 要求 2 字节(IV-BS2);不符返回 nil
- [ ] T016 [P] 新建 `app/macos/Tests/BleWidgetTests/BatteryStatusTests.swift`(XCTest),覆盖:
  - 整板:1 字节 `0..=100` → `.percent(n)`;`255` → `.unavailable`;`101..=254` → `.unavailable`
  - 整板:0 字节或 ≥ 2 字节 → `parse` 返回 nil(IV-BS1)
  - 分体:2 字节合法组合;0 / 1 / ≥ 3 字节 → nil(IV-BS2)
  - sentinel 一侧 + 正常另一侧(例如 `[255, 72]` → `.split(.unavailable, .percent(72))`)
- [ ] T017 [P] 新建 `app/macos/Sources/BleWidgetCore/StalenessTracker.swift`(public actor 或 class)。按 `data-model.md` §KeyboardLink + `contracts/macos-ui.md` §3 的 3 秒规则:
  - public method `recordNotify(fieldKey: String, at: TimeInterval)` 记录单字段 lastNotifyAt(单调时钟,`CFAbsoluteTimeGetCurrent()` 或 `DispatchTime.now()`)
  - public method `isStale(fieldKey: String, now: TimeInterval) -> Bool`:`now - lastNotifyAt >= 3.0` 返回 true
  - public method `forceStaleAll()`:断连事件立即把所有字段标陈旧
  - public method `clearStale(fieldKey:)`:新 notify 恢复实时
  - 1 Hz 定时检查由 BLEClient 调用(此 struct 本身不启动 Timer,保持可单测)
- [ ] T018 [P] 新建 `app/macos/Tests/BleWidgetTests/StalenessTrackerTests.swift`(XCTest),覆盖:
  - `recordNotify` 后立即 `isStale == false`
  - 2.99 s 后 `isStale == false`;3.0 s 后 `isStale == true`;3.0 + ε 后仍 true
  - `forceStaleAll` 后所有字段立即 stale
  - 新 `recordNotify` 后 `isStale == false`(单字段恢复)
  - 单调时钟方向性:注入"回退"时间戳 → 不改变 isStale 返回(永不负)

### BLE 发现与订阅骨架

- [ ] T019 修改 `app/macos/Sources/BleWidgetCore/BLEClient.swift`,在既有 `AA440AA1-…` 发现订阅路径后追加:
  - 新常量 `connectivityCharacteristicUUID = CBUUID(string: "AA440AA2-F5ED-4C48-84A1-8062D20D3D55")`
  - 新常量 `batteryCharacteristicUUID = CBUUID(string: "AA440AA3-F5ED-4C48-84A1-8062D20D3D55")`
  - 在 `peripheral(_:didDiscoverCharacteristicsFor:error:)` 中按存在性订阅两个新 characteristic(各自 READ 一次 + 启用 CCC NOTIFY)
  - 在 `peripheral(_:didUpdateValueFor:error:)` 中按 UUID 分发到两个新 handler:`handleConnectivityUpdate(_: Data)` 调用 `ConnectivityStatus.parse(...)`;`handleBatteryUpdate(_: Data)` 调用 `BatteryStatus.parse(...)`(需要 CapabilityMatrix.isSplit,从 cache 中取)
  - 新 delegate protocol 方法(或 Combine publisher)把两个 struct 发给上层(FloatingPanel 消费)
  - 不启动 UI 层改动;本 task 只负责 wire 到 BleWidgetCore 的事件流
  - **依赖**:T011/T013/T015/T017 的类型存在
- [ ] T020 修改 `app/macos/Sources/BleWidget/AppDelegate.swift`,新增 `DiagnosticsLogger` static 实例(或新建 `app/macos/Sources/BleWidget/DiagnosticsLogger.swift` 文件),按 `contracts/macos-ui.md` §5 用 `os.Logger(subsystem: "com.keybeacon.app", category: ...)` 发出以下事件 category:`capability` / `profile` / `battery` / `staleness` / `connection`。暴露 public API 给 BLEClient 调用(例如 `DiagnosticsLogger.capability.inconsistent(...)`)。所有字段用 `%{public}` 可见。
- [ ] T021 修改 `app/macos/Sources/BleWidget/FloatingPanel.swift`,新增「连接与电量」卡片**整张外壳**(标题 + 空内容区),按 `contracts/macos-ui.md` §1.1 的卡片级可见性规则:
  - GATT 服务里没有 `AA440AA2-…` → 整张**不渲染**(KBP 1.0 固件完全隐藏)
  - `AA440AA2-…` 存在 → 卡片渲染,但本 task 内各行**全部为空**(行渲染在 US phase 中依序填入)
  - 卡片位于层/修饰键区块下方
  - 布局不打断现有 KBP 1.0 UI
- [ ] T022 修改 `conformance/conformance_tool.py` 的 `--json` 输出,追加 Foundational 阶段的 schema 字段:`declared_minor`(`"1.0"` / `"1.1"` / `"unknown"`)、`characteristics.AA440AA2` / `AA440AA3`(各含 `present` / `properties` / `ccc`)、`capability_bits`(含 `raw` + 6 个字段 bool,仅 declared_minor == "1.1" 时存在)、`field_support` 骨架(所有字段先置 `"skipped"`,字段级实现在 US phase 中填充)。确保 J-1..J-4 不变量在 Foundational 下已成立。

**Checkpoint**: 协议文档英中就绪 · 一致性 CLI 骨架能跑 `--help` + `--json` · CapabilityMatrix / ConnectivityStatus / BatteryStatus / StalenessTracker 全部类型就绪并单测通过 · BLEClient 已订阅两个新 characteristic · FloatingPanel 卡片外壳按能力位整张显隐。四个 user story 可独立实现 UI 行与 CLI 字段检查。

---

## Phase 3: User Story 1 — 一眼看清主机连接与当前 profile(Priority: P1)🎯 MVP

**Goal**: 用户打开面板,一眼看到键盘是否连上主机、当前位于第几 profile 槽位(1–5),以及该槽位是否 open/待配对。切换 profile 时面板实时跟随。(spec §User Story 1 + Acceptance Scenarios 1-3)

**Independent Test**: 单接一把兼容键盘,运行 app,在不同 profile 之间切换 / 让键盘与主机断连重连,确认面板显示的 profile 索引、连接状态、open 状态与键盘实际状态一致;SC-002 的 P50 ≤ 1 s / P95 ≤ 2 s 可测;SC-001 的"打开面板到看清 ≤ 2 s"可测。

### Implementation for User Story 1

- [ ] T023 [US1] 修改 `app/macos/Sources/BleWidget/FloatingPanel.swift` 新增**主机连接行**,按 `contracts/macos-ui.md` §2.1:圆点(绿=已连接 / 灰=未连接)+ 文案"已连接" / "未连接";`lastDisconnectReason ≠ unknown` 且 connected=0 时文案追加"(超时)" / "(主动断开)";陈旧状态 50% 透明度 + 右侧"最后更新 hh:mm:ss"(消费 StalenessTracker)。IV-K1:`CapabilityMatrix.hasHostConnection = 0` 时**整行隐藏**(不占位)。
- [ ] T024 [US1] 修改 `app/macos/Sources/BleWidget/FloatingPanel.swift` 新增 **Profile 槽位视图行**,按 `contracts/macos-ui.md` §2.2:n 个圆形徽标(n = `profile_max_slots`)水平排列,索引居中;当前 index 徽标**粗边框 + 填充**,其他**细边框 + 空心**;`profile_open = 1` 的徽标**虚线边框 + 右上角"待配对"小字**;只读显示(本期不支持写回键盘)。IV-P2:`hasProfile = 0` → 整行隐藏;IV-P1:`profile_index > profile_max_slots` → UI 显示 index 钳制在 `profile_max_slots`,BLEClient 侧已经 handle 诊断日志。
- [ ] T025 [P] [US1] 修改 `conformance/conformance_tool.py` 实现 C8 中 `host_state`(byte[1])与 `profile_index/profile_max_slots`(byte[2..3])字段的 PASS/FAIL 检查:host_state 的 bits 3–7 reserved 必须为 0,否则 WARN;`profile_index` 的 bits 0–6 ≤ `profile_max_slots`(越界 FAIL);按声称的 `has_host_connection` / `has_profile` capability bit 决定 PASS / SKIP。`--json` 的 `field_support.host_connection` 与 `field_support.profile` 填充 `"supported"` / `"unsupported"` / `"malformed"`。
- [ ] T026 [P] [US1] 新建 `conformance/tests/test_us1_fields.py`(pytest),覆盖 host_state 与 profile 字段解析:bit 组合、越界 index、全 0 字节、reserved 位非零;所有测试独立于 BLE I/O(传入 raw bytes)。
- [ ] T027 [US1] 执行 `specs/001-connectivity-power/quickstart.md §3.1 剧本 A`(主机连接 + profile 可见),手工验证两个 When 均 ≤ 1 s;抓取 `log stream --predicate 'subsystem == "com.keybeacon.app" AND category == "connection"'` 确认 `connection.state_changed` 日志每次翻转各发一次。

**Checkpoint**: US1 可独立 ship。打开面板能看到主机连接状态 + profile 槽位视图,FR-002 / FR-003 / FR-017 验收通过;SC-001 / SC-002(host/profile 部分)可测。

---

## Phase 4: User Story 2 — 分体掉线与每半电量可视化(Priority: P1)

**Goal**: 用户看分体键盘面板,左右半任何一侧掉线或某一侧电量偏低都立即可见,无需翻键盘背面或接 USB 排查。(spec §User Story 2 + Acceptance Scenarios 1-3)

**Independent Test**: 使用 central/peripheral 分体键盘,人为断开 peripheral 侧(关机或移出范围),面板标记为"离线";对比两侧实际电量读数与面板显示值误差 ≤ ±5pp(SC-003);一把**非分体**键盘单独验证只显示整机电量(IV-S1)。

### Implementation for User Story 2

- [ ] T028 [US2] 修改 `app/macos/Sources/BleWidgetCore/BLEClient.swift`,在 Connectivity notify handler 中:识别到 `CapabilityMatrix.isSplit = 1` 且 Battery characteristic (`AA440AA3-…`) 存在时,把 isSplit 传递给 `BatteryStatus.parse(..., isSplit: true)`;长度不匹配(IV-BS1/IV-BS2)→ 丢弃并调用 `DiagnosticsLogger.battery.length_mismatch(...)`。整板场景复用同一 handler,但传 `isSplit: false`。
- [ ] T029 [US2] 修改 `app/macos/Sources/BleWidget/FloatingPanel.swift` 新增**分体在/离线行**,按 `contracts/macos-ui.md` §2.3:左右两个标签"左 / 右",各带状态点(绿=online / 红=offline);offline 时红点 + 文案"离线" + 该半电量数字固定在**最后已知值 + 时间戳**(IV-S2)。仅当 `isSplit = 1 && hasSplitLink = 1` 时渲染。
- [ ] T030 [US2] 修改 `app/macos/Sources/BleWidget/FloatingPanel.swift` 新增**电量行**,按 `contracts/macos-ui.md` §2.4:
  - `is_split = 0` → 单一横向条 + 数字百分比
  - `is_split = 1` → 两条横向条(左 / 右)并排
  - `percent = 255`(sentinel)→ 条形体灰 + 文案"读取失败",不显示数字
  - 电量条填充颜色/长度 **对应原始百分比值**;展示层允许 3 秒滑动平均但 **MUST NOT** 影响数字判读(IV-B2 / U-3)
  - 本行**不**包含充电图标(充电图标在 US4)
- [ ] T031 [P] [US2] 修改 `conformance/conformance_tool.py` 实现 C8 中 `split_link_flags`(byte[4])与 C9(整个 Battery characteristic)检查:
  - split_link bit 0/1 reserved 位(bits 2–7)必须 0,否则 WARN
  - `has_split_link = 1` 但 `is_split = 0` → FAIL(P-C1 违规)
  - Battery characteristic payload 长度与 is_split 一致:is_split=0 ⇒ 长度 =1、is_split=1 ⇒ 长度 =2;不符 → FAIL(C9 核心)
  - 电量字节 101–254 → WARN(保留值);255 → PASS(sentinel 合法)
  - `--json` 的 `field_support.split_link` / `overall_battery` / `left_battery` / `right_battery` 填充
- [ ] T032 [P] [US2] 新建 `conformance/tests/test_us2_fields.py`(pytest),覆盖 split_link + battery 解析:is_split 组合、长度 mismatch、sentinel 单侧、101–254 保留值。
- [ ] T033 [US2] 执行 `specs/001-connectivity-power/quickstart.md §3.2 剧本 B`(分体掉线 + 每半电量)和 §3.4 剧本 D(非分体键盘整机电量,验证 IV-S1):手工验证两次翻转在时限内发生;两条电量条数字与键盘实际读数相差 ≤ 5pp(SC-003);整板键盘不渲染左右半字段。

**Checkpoint**: US2 可独立 ship。分体键盘面板显示左右半状态与电量;FR-004 / FR-005 / Acceptance Scenario 3(非分体整机电量)验收通过;SC-002(split 部分)/ SC-003 可测。

---

## Phase 5: User Story 3 — 当前输出端点可见(Priority: P2)

**Goal**: 用户在面板上看到此刻键击实际送往的是 USB 还是 BLE,切换时实时反馈。(spec §User Story 3 + Acceptance Scenarios 1-2)

**Independent Test**: 让键盘在 USB 直连与 BLE 之间来回切换(拔插 USB 或触发 `BT_SEL` 快捷键),面板的输出端点字段在 1 秒内准确跟随(SC-002)。

### Implementation for User Story 3

- [ ] T034 [US3] 修改 `app/macos/Sources/BleWidget/FloatingPanel.swift` 新增**输出端点行**,按 `contracts/macos-ui.md` §2.5:单行文案"输出:USB" / "输出:BLE";保留 raw code(≥ 3)时显示"输出:未知(0x0n)"(IV-O2);`hasOutputEndpoint = 0` → 整行隐藏(IV-O1)。
- [ ] T035 [P] [US3] 修改 `conformance/conformance_tool.py` 实现 C8 中 `output_endpoint`(byte[5])字段检查:取值 0..255 全部合法但 0/1/2 为语义已定、3..255 为保留(WARN "non-canonical endpoint code: 0x_" 但不 FAIL);`--json` 的 `field_support.output_endpoint` 填充。
- [ ] T036 [P] [US3] 修改 `conformance/tests/test_us1_fields.py` **或**新建 `conformance/tests/test_us3_fields.py`(两种方式都接受,选独立新文件以符合 [P]),覆盖 output_endpoint 字节 0/1/2/3/255 的映射与保留值提示。
- [ ] T037 [US3] 执行 `specs/001-connectivity-power/quickstart.md §3.3 剧本 C`(输出端点切换):USB → BLE → USB 来回,两个切换均 ≤ 1 s;抓取 `connection` category 的日志。

**Checkpoint**: US3 可独立 ship。面板显示输出端点行;FR-006 验收通过;SC-002(endpoint 部分)可测。

---

## Phase 6: User Story 4 — 充电状态(可选,依赖硬件)(Priority: P3)

**Goal**: 键盘硬件具备充电检测能力时,面板显示某一侧(或整机)是否正在充电;不支持的键盘**完全不显示**该字段(SC-006)。(spec §User Story 4 + Acceptance Scenarios 1-2)

**Independent Test**: 支持充电检测的键盘接上充电,面板显示"充电中";切换到不支持的键盘,面板**不显示**该字段(或标记为"不支持")而非错误状态。

### Implementation for User Story 4

- [ ] T038 [US4] 修改 `app/macos/Sources/BleWidget/FloatingPanel.swift` 新增**充电图标**(在 §2.4 电量条右上角,**不**单独成行),按 `contracts/macos-ui.md` §2.4:支持充电(左半或整板看 `hasLeftCharging`,右半看 `hasRightCharging`)且对应 `chargingFlags.left/rightCharging = 1` 时,对应侧电量条右上角显示闪电图标;对应半 `has_*_charging = 0` → 该半**完全不**渲染充电图标(电量 % 仍可见,IV-S3);两侧硬件不对称时允许一侧可见、另一侧完全隐藏;**禁止**显示"未充电"占位(FR-007 + SC-006)。
- [ ] T039 [P] [US4] 修改 `conformance/conformance_tool.py` 实现 `charging_flags`(byte[6])字段检查:bits 2–7 reserved 必须 0 → WARN;`has_left_charging = 0` 但 byte[6] bit 0 非 0 → WARN(应清零);`has_right_charging = 0` 但 byte[6] bit 1 非 0 → WARN;`has_right_charging = 1` 但 `is_split = 0` → FAIL(P-C5 违规);`--json` 的 `field_support.left_charging` / `field_support.right_charging` 分别填充。注意:不是 C7–C12 的独立新条目(落在 C8 内),C11 的节流规则对 charging 不生效(状态性字段)。
- [ ] T040 [US4] 执行 `specs/001-connectivity-power/quickstart.md §3.4 剧本 D`(充电字段不占位):当前 Totem 固件典型未实现 charger GPIO → 面板**完全不出现**充电图标、文案、占位区域;一致性 CLI 的 JSON 中 `field_support.left_charging == "unsupported"` **且** `field_support.right_charging == "unsupported"`。

**Checkpoint**: US4 可独立 ship。支持的键盘显示充电图标,不支持的键盘完全隐藏;FR-007 验收通过;SC-006(100% 不出现误导性"未充电")可测。

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: 跨 US 的完整性验证、Constitution 合规最终 sweep、CI 冒烟。

- [ ] T041 执行 `specs/001-connectivity-power/quickstart.md §3.5 剧本 E`(陈旧 3 秒阈值):断连立即陈旧 + Connectivity 任务卡死 > 3 秒后字段降级,恢复后立即回实时;抓取 `log stream --predicate 'subsystem == "com.keybeacon.app" AND category == "staleness"'` 看到 `staleness.field_stale` 日志(FR-015 验收)。
- [ ] T042 执行 `specs/001-connectivity-power/quickstart.md §3.6 剧本 F`(向后兼容):把 Totem 刷回 KBP 1.0 固件(或换一把 1.0-only 键盘),新 app 整张「连接与电量」卡片不出现、层/修饰键显示正常;一致性 CLI 的 `declared_minor = "1.0"`,`exit_code = 0`,C7–C12 全 SKIP(FR-016 + SC-004 验收)。
- [ ] T043 执行 `specs/001-connectivity-power/quickstart.md §3.7 剧本 G`(完整连环场景):主机断连 → 10 s 后重连 → 切 profile 1→3 → 切输出 USB→BLE → 关 peripheral → 15 s 后恢复 → 恢复 USB 输出 → 全部回到实时态。全程无崩溃、无"面板与实际不一致 ≥ 2 秒"的卡顿(SC-007 验收)。
- [ ] T044 [P] 执行 `specs/001-connectivity-power/quickstart.md §5 跨平台 CLI 平台矩阵冒烟`:在 Linux(Ubuntu 22.04,bluetoothd 已启动)与 Windows 10/11(PowerShell + Python 3.11)上分别 `python conformance/conformance_tool.py --help` + `--timeout 5`;两平台**不崩**、无键盘时正确退出 2(env error)(FR-012 验收)。**另于** macOS/Linux 任一有键盘的环境执行一轮 `python conformance/conformance_tool.py --timeout 15`,记录 wall-clock,**断言单轮 ≤ 60 秒**(SC-005 验收);如超时需在报告中标注环境信息、键盘型号与瓶颈阶段(discover / connect / observe / enumerate)。
- [ ] T045 [P] 执行 `specs/001-connectivity-power/quickstart.md §6 回归套件`:`cd app/macos && swift test`,确保 KBP 1.0 既有的 KeyboardStatusTests / CompatibilityTests / KeyboardIdentityTests / MigrationTests 全部 PASS **不得退化**;新增的 4 个 Tests 全部 PASS。
- [ ] T046 Constitution Principle VI 双语最终 sweep:逐一确认 `protocol/README.md` §14、`protocol/CHANGELOG.md` 1.1.0 条目、`conformance/CONFORMANCE.md` A-group 节、`conformance/checklist.md` C7–C12、仓库根 `README.md` Roadmap A 节**均为英中双语 side-by-side**,规范语 (MUST → 必须 / SHOULD → 应 / MAY → 可) 稳定渲染,中文为 full mirror 不是 summary(Principle VI 不变量)。
- [ ] T047 Constitution Principle IV 可观测降级最终验证:在 Totem 上触发所有可能的 degradation 情形(field-level capability false、field going stale、length mismatch、out-of-range value),通过 `log stream` 过滤 `com.keybeacon.app` subsystem 的全部 category,确认结构化诊断日志**每个 degradation 事件各发一次**(FR-018 验收)。
- [ ] T048 Lint + format(macOS):`cd app/macos && swift build -c release`(确保无 warning 升为 error);Python side `python3 -m py_compile conformance/conformance_tool.py conformance/tests/*.py`;`pytest conformance/tests/ -v`(全 PASS)。

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1, T001–T003)**: 无前置,立即开始
- **Foundational (Phase 2, T004–T022)**: 依赖 Setup 完成;**阻塞所有 user story**
  - T004–T006(协议文档)可与 T007–T010(CLI)并行;与 T011–T018(macOS core)并行
  - T019 依赖 T011/T013/T015/T017(类型就绪)
  - T020 可与 T019 并行(不同文件,只是 BLEClient 会调用 DiagnosticsLogger,整合点在 Phase 3+ 的 handler)
  - T021 可与 T019/T020 并行(FloatingPanel 外壳 vs BLEClient 事件源)
  - T022 依赖 T009 完成(T009 建骨架,T022 扩充 JSON schema)
- **User Stories (Phase 3–6)**: 全部依赖 Foundational;**US1 (P1) 与 US2 (P1) 可并行**(不同 UI 行、不同 CLI 字段检查、不同 Test 文件);US3/US4 可在 US1/US2 之后或并行(都只改 FloatingPanel 不同区段)
  - 实际上 `FloatingPanel.swift` 是单一文件,四个 US 的 UI 行追加会 serialize(非 [P] 跨 US),但各自不冲突、合并简单
  - `conformance_tool.py` 同理,但 CLI 字段检查按 US 划分到独立函数后,可并行实现
- **Polish (Phase 7, T041–T048)**: 依赖所有要交付的 user story 完成;各任务间大部分 [P]

### User Story Dependencies

- **US1 (P1)**: Foundational 完成后立即可开始;**无依赖**其他 story
- **US2 (P1)**: Foundational 完成后立即可开始;**无依赖**其他 story;**可与 US1 并行**(不同开发者)
- **US3 (P2)**: Foundational 完成后立即可开始;**无依赖**其他 story
- **US4 (P3)**: Foundational 完成后立即可开始;**无依赖**其他 story;视觉依附 US2 的电量条右上角,但仅视觉布局,不是代码依赖——如果先做 US4、后做 US2,充电图标也能作为独立卡片呈现

### Within Each User Story

- 模型 (`BleWidgetCore` 的 struct) 先于 UI (`FloatingPanel` 行)
- CLI 字段检查 (`conformance_tool.py`) 与 UI 行可并行
- XCTest 更新与 UI 行可并行(单测只覆盖解析,与 UI 布局无关)
- 手工 quickstart 剧本**最后**执行(验收 gate)

### Parallel Opportunities

**Phase 1**:T002 / T003 并行(T001 为前置,串行)。
**Phase 2(协议 + 一致性文档)**:T004 / T005 / T006 / T007 / T008 / T009 / T010 全部 [P] 并行(不同文件,无依赖)。
**Phase 2(macOS core)**:T011 / T012 / T014 / T015 / T016 / T017 / T018 全部 [P] 并行;T013 依赖 T011,T019 依赖 T011/T013/T015/T017,T020 / T021 并行,T022 依赖 T009。
**US1**:T023 与 T024 都改同一文件 `FloatingPanel.swift`(非 [P]),但 T025 / T026 独立(两个 [P]);T027 验收 serial。
**US2**:T028 → T029 / T030(FloatingPanel,非 [P] 跨 UI 行)× T031 / T032(CLI + test,[P]);T033 验收 serial。
**跨 US 并行**:若有两个开发者,一人 US1、一人 US2 完全独立;US3 + US4 可穿插。
**Phase 7**:T044 / T045 / T046 / T047 / T048 全部 [P] 并行。

---

## Parallel Example: Foundational 的协议 + 文档层

```bash
# 启动 Foundational 的 7 个并行文档任务(T004–T010):
Task: "T004 追加 protocol/README.md §14 KBP 1.1 可选特征(英中双语)"
Task: "T005 追加 protocol/CHANGELOG.md 1.1.0 条目(英中)"
Task: "T006 更新仓库根 README.md Roadmap A 节(英中)"
Task: "T007 追加 conformance/checklist.md C7–C12(英中)"
Task: "T008 更新 conformance/CONFORMANCE.md A-group 节(英中)"
Task: "T009 新建 conformance/conformance_tool.py 跨平台骨架"
Task: "T010 新建 conformance/tests/test_payload_parsing.py 纯函数单测"

# 再启动 Foundational 的 macOS core 并行任务:
Task: "T011 新建 CapabilityMatrix.swift"
Task: "T012 新建 CapabilityMatrixTests.swift"  # 可与 T011 并行(TDD 风格 or 同步)
Task: "T015 新建 BatteryStatus.swift"
Task: "T016 新建 BatteryStatusTests.swift"
Task: "T017 新建 StalenessTracker.swift"
Task: "T018 新建 StalenessTrackerTests.swift"
Task: "T020 修改 AppDelegate.swift 新增 DiagnosticsLogger"
Task: "T021 修改 FloatingPanel.swift 卡片外壳"
```

## Parallel Example: User Story 1 的 CLI 字段与单测

```bash
# 完成 Foundational 后,启动 US1 的两个 [P] 任务:
Task: "T025 修改 conformance_tool.py 实现 C8 host_state + profile 字段检查"
Task: "T026 新建 conformance/tests/test_us1_fields.py host/profile 单测"
```

---

## Implementation Strategy

### MVP First(US1 Only)

1. 完成 Phase 1 Setup(T001–T003)
2. 完成 Phase 2 Foundational(T004–T022)
3. 完成 Phase 3 US1(T023–T027)
4. **STOP & VALIDATE**:单接一把兼容键盘,quickstart 剧本 A 全 PASS → MVP 可 demo
5. 可选:在此节点合并到 main,ship 一轮 KBP 1.1 的 **最低可用切片**

### Incremental Delivery(推荐)

1. Setup + Foundational → 基础就绪
2. US1(host + profile)→ MVP demo
3. US2(split + battery)→ P1 全交付,核心价值主张完成
4. US3(output endpoint)→ P2 补齐,无屏键盘全场景可观察
5. US4(charging)→ 锦上添花,硬件支持的键盘用户受益
6. Polish → quickstart 全剧本 + 跨平台冒烟 + Constitution Principle VI 双语 sweep + XCTest 回归

每个增量之间可以独立合并、独立 release 一个 patch tag(例如 `app/macos` 的 1.1.0-us1 / 1.1.0-us2 ...)。

### Parallel Team Strategy

若有 2–3 名开发者:

1. 全员协作完成 Setup + Foundational(T011–T022 内部 [P] 分工:A 做协议文档,B 做 CLI,C 做 macOS core)
2. Foundational 完成后:
   - Developer A:US1(T023–T027)
   - Developer B:US2(T028–T033)
   - Developer C:US3(T034–T037)+ US4(T038–T040,串行穿插)
3. 所有 user story 合并后,全员协作 Polish(T041–T048,大部分 [P])

---

## Notes

- **测试策略**:XCTest 覆盖所有 `BleWidgetCore` 新 public 类型(constitution Testing & Verification Discipline);pytest 覆盖 `conformance_tool.py` 纯函数;UI 层通过 quickstart 手工剧本验收。
- **双语合规**(Constitution Principle VI):T004 / T005 / T006 / T007 / T008 **MUST** 英中 side-by-side 落地;T046 为最终 sweep 验证。
- **向后兼容**(Constitution Principle II + SC-004):T042 为硬性 gate — 新 app 连 KBP 1.0 固件必须「连接与电量」卡片整张隐藏、层/修饰键显示正常、CLI exit 0。
- **可观测降级**(Constitution Principle IV + FR-013/U-1):T038 / T047 为硬性 gate — 不支持的字段 100% 不占位。
- **用户删除规则**:T001 用 `git mv` 备份原 PyObjC 工具,**不**使用 `rm` 命令(符合用户规则)。
- **工具不混用**:新 `conformance_tool.py` **MUST NOT** import PyObjC;legacy `conformance_tool_macos.py` 保留 PyObjC 栈不动。
- **文件冲突提示**:`FloatingPanel.swift` 会被 US1/US2/US3/US4 相继修改,各 US 内部的两个 UI 行任务(例如 T023/T024)也在同一文件,故这些任务**没有 [P]** 跨彼此;实际 merge 时按行追加,冲突面极小。
- **验证顺序**:每个 US 的最后一个任务是对应 quickstart 剧本的手工执行,**MUST** 在合并前完成。
- Commit 后每个任务或逻辑组一次(用户不显式要求 commit 则 **不自动 commit**)。
- 任意 checkpoint 都可停下来独立验证对应 user story。
