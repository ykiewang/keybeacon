# Feature Specification: 连接与电量指标(Roadmap A)

**Feature Branch**: `001-connectivity-power`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "新建分支，按照我们的roadmap开发A图中指标"

## 概述

将 Roadmap A「连接与电量」中的候选指标正式纳入 KeyBeacon 协议并端到端落地。覆盖:主机连接
状态、当前 BLE profile(槽位 1–5 及待配对状态)、左右半连接状态、每半电量、当前输出端点
(USB/BLE)、以及可选的充电状态。目标是让用户在**无屏键盘**(特别是无线分体)场景下,仅凭
macOS 菜单栏/悬浮面板即可一眼看清键盘的连接与电量全貌。

该特性以 **KBP 1.1 MINOR 增量**形式交付:新增一组可选 BLE 特征,老版本 app 忽略不认识的
特征即可继续工作。可行性评估基于 ZMK 事件模型,但协议本身与固件实现解耦。

## Clarifications

### Session 2026-10-09

- Q: 键盘断连后,面板上该字段的"实时值"要过多少秒没刷新才降级为"最后已知值(灰显 + 带时间戳)"? → A: 3 秒无更新即视为陈旧
- Q: app 该用什么机制来识别"这是分体键盘(需要显示左右半字段)"? → A: KBP 1.1 的能力位中新增 1 bit `is_split`,由固件声明;ZMK 参考实现绑定 `CONFIG_ZMK_SPLIT`(或 `CONFIG_ZMK_SPLIT_ROLE_CENTRAL`)。不复用 BAS 实例数、不依赖字段存在性反推。
- Q: 可选的"充电状态"字段在固件支持上报时,它的取值集合该如何定义? → A: 二态 `{charging, not_charging}`;硬件无法可靠区分"充满"的,整字段靠能力位隐藏,**不**广播 `full` 或 `unknown` 占位。
- Q: 这组新增字段的 BLE notify 发送频率上限该怎么定? → A: 状态性字段(主机连接、profile、分体在线、输出端点、充电状态)**变即发**;数值性字段(每半/整机电量百分比)**变化 ≥ 1 个百分点或每 1 秒最多 1 次**,两者满足其一即可触发 notify。KBP 1.0 既有的"snapshot 未变不发"原则继续适用。
- Q: `conformance/` 下的 A 组字段自测工具,这期要在哪个运行环境里能跑? → A: 跨平台 CLI(Python + bleak 或等价的跨平台 BLE 库),macOS / Linux / Windows 三平台均可运行。协议规范本身保持 OS 无关;工具实现与 macOS app 代码解耦,不依赖 CoreBluetooth。
- Q: 当分体键盘左右半的充电检测硬件能力不同(例如只有左半有 charger GPIO)时,`capability_bits` 该如何按半声明支持? → A: **扩展协议位分配**。bit 5 转义为 `has_left_charging`(整板时为 overall);bit 6 用作 `has_right_charging`(仅 `is_split = 1` 时有效);bit 7 保留给下一个 MINOR。两侧不对称时 UI 按半各自显隐充电图标。
- Q: 键盘已连接但 BLE 链路长时间无 notify 时,app 要不要主动做一次兜底 READ? → A: **不做**。删除 FR-014 原本"兜底刷新 ≥ 10 秒"条款,改为纯事件驱动 + 被动 stale 检测(由 FR-015 的 3 秒无 notify 自动降级 + 断连事件立即降级充当兜底),与宪章 Principle IV「Observable Degradation Over Guessing」一致;plan 的 Performance Goals 与 tasks.md 维持现状。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 一眼看清主机连接与当前 profile (Priority: P1)

用户在使用无线分体键盘时,打开 macOS 菜单栏/悬浮面板,立刻能看到:键盘是否已连上当前主机、
当前位于第几个 BLE profile 槽位(1–5),以及该槽位是否处于"待配对/open"状态。切换 profile
时,面板上的高亮槽位实时跟随变化。

**Why this priority**: 无屏键盘最常见、也是用户最先会关心的问题就是"我现在连的是哪台
机器、键盘到底连上了没"。这是 A 组指标的最低可行切片——只实现这一条就已经比现状更有价值。

**Independent Test**: 单接一把兼容键盘,运行 app,在不同 profile 之间切换 / 让键盘与主机
断连重连,确认面板显示的 profile 索引、连接状态、open 状态与键盘实际状态一致。

**Acceptance Scenarios**:

1. **Given** 键盘已通过 profile #2 连上当前主机, **When** 用户打开菜单栏面板, **Then** 面板
   显示"已连接 · profile 2 / 5",且 #2 槽位高亮。
2. **Given** 键盘已连接, **When** 用户在键盘上切到 profile #4(尚未配对任何设备), **Then**
   面板在 1 秒内更新为"profile 4 / 5 · 待配对(open)"。
3. **Given** 键盘与主机因距离过远断连, **When** 断连发生, **Then** 面板在 2 秒内从"已连接"
   更新为"未连接",并保留最后一次已知的 profile 槽位信息。

---

### User Story 2 - 分体掉线与每半电量可视化 (Priority: P1)

用户使用无线分体键盘时,左右半任何一侧掉线或某一侧电量偏低都应立即可见,而不需要去翻键盘背面
的指示灯或连 USB 排查。

**Why this priority**: 分体键盘的"某一半没跟上"是无屏场景下最隐蔽也最常见的故障模式;单独
显示每半电量则是用户决定"先充哪一半"的关键信息。两者共同支撑了 A 组对"分体可观测性"的核心
价值主张,因此与 Story 1 同为 P1。

**Independent Test**: 使用一把 central/peripheral 架构的分体键盘,人为断开 peripheral 侧
(例如关机或移出范围),确认面板能标记该侧为"离线";同时对比两侧实际电量读数与面板显示值,
误差在 ±5% 以内即视为通过。

**Acceptance Scenarios**:

1. **Given** 分体键盘左右两半均在线, **When** 用户查看面板, **Then** 面板同时显示左半与
   右半的电量百分比(0–100%)。
2. **Given** 分体键盘右半掉线, **When** 掉线发生, **Then** 面板在 2 秒内将右半标记为"离线"
   并保留最后一次已知电量读数,同时视觉上明显区分于"在线但低电"。
3. **Given** 一把**非分体**(整板)键盘, **When** 用户查看面板, **Then** 面板只展示整机电量
   一项,不虚构或占位显示"左右半"字段。

---

### User Story 3 - 当前输出端点可见 (Priority: P2)

用户能在面板上看到此刻键击实际送往的是 USB 还是 BLE(以及切换时的实时反馈),避免发生
"以为在 BLE 上实际走的是 USB、或反之"的困惑。

**Why this priority**: 该信息相对不如 Story 1/2 紧迫,但对多端点用户(常在同一台机器 USB
和 BLE 之间切换)价值很高,且 ZMK 可行性高、协议代价小,适合随 P1 一同交付。

**Independent Test**: 让键盘在 USB 直连与 BLE 之间来回切换(例如拔插 USB),确认面板的输出
端点字段在 1 秒内准确跟随。

**Acceptance Scenarios**:

1. **Given** 键盘通过 USB 直连并选用 USB 为输出端点, **When** 用户查看面板, **Then** 面板
   显示输出 = "USB"。
2. **Given** 键盘保持 USB 物理连接但主动切换到 BLE 输出, **When** 切换发生, **Then** 面板
   在 1 秒内更新为输出 = "BLE"。

---

### User Story 4 - 充电状态(可选,依赖硬件) (Priority: P3)

当键盘硬件具备充电检测能力时,面板能显示某一侧(或整机)当前是否正在充电。

**Why this priority**: ZMK 可行性低(多数板无充电检测引脚),该字段必须优雅降级为"未知/不
支持",因此只能作为锦上添花项处理,优先级最低。

**Independent Test**: 用支持充电检测的键盘接上充电,确认面板显示"充电中";切换到不支持的
键盘,确认面板不显示该字段或显示为"不支持"而非错误状态。

**Acceptance Scenarios**:

1. **Given** 键盘硬件支持充电检测且正在充电, **When** 用户查看面板, **Then** 面板显示该侧
   "充电中"图标/文案。
2. **Given** 键盘不上报充电能力, **When** 用户查看面板, **Then** 面板**不展示**充电字段
   (或标记为"不支持"),绝不显示误导性的"未充电"。

---

### Edge Cases

- **特征缺失**:老固件只支持 KBP 1.0,未广播本次新增特征。app 必须优雅降级,只显示已有的
  层/修饰键信息,不出现"空白卡片"或崩溃。
- **部分字段支持**:固件支持 profile 但不上报每半电量。app 必须按字段级进行能力探测,逐项
  显示或隐藏,不采用"全有或全无"策略。
- **profile 索引越界**:固件声称有 N 个 profile 槽位,但上报了 N+1。app 必须钳制在声明范围
  内并记录一次结构化警告。
- **电量读数抖动**:短时间内电量百分比上下跳动。app 展示层应做小幅平滑(例如 3 秒窗口),
  但协议层**必须**透传原始值。
- **断连后残留**:键盘断连后,面板必须明确区分"最后已知值"与"实时值",不能让陈旧数据看
  起来像实时数据。
- **输出端点字段固件不上报**:应隐藏输出端点卡片,而非默认显示 "USB" 或 "BLE"。

## Requirements *(mandatory)*

### Functional Requirements

**协议层(KBP 1.1,`protocol/`)**

- **FR-001**: 协议 MUST 以 **MINOR 增量**(KBP 1.1)方式新增一组可选 BLE 特征,用于暴露
  A 组指标;老版本应用在不识别这些特征时 MUST 能继续按 KBP 1.0 正常工作。
- **FR-002**: 协议 MUST 规范"主机连接状态"字段,至少包含:已连接 / 未连接 两种状态,以及
  最后一次状态变更的来源(主动断开 / 超时 / 未知)。
- **FR-003**: 协议 MUST 规范"当前 BLE profile"字段,包含:槽位索引(1 起、最大槽位数由固
  件声明)、该槽位是否处于 open(待配对)状态。
- **FR-004**: 协议 MUST 规范"分体连接状态"字段,支持 central 侧上报 peripheral 侧的在/离线。
  是否为分体键盘 MUST 由固件通过能力位中的 `is_split` 位显式声明(见 FR-009),app
  **不得**通过"是否收到左右半字段"或"是否存在第二个标准 BAS 实例"等旁路信号反推。对
  `is_split = 0` 的键盘,分体连接状态字段 MUST 可缺省且 app MUST NOT 渲染该字段。
- **FR-005**: 协议 MUST 规范"每半电量"字段,仅当 `is_split = 1` 时才可能上报左半和右半电量
  百分比(0–100%);`is_split = 0` 的键盘退化为"整机电量"单字段,其余字段 MUST 不出现。
- **FR-006**: 协议 MUST 规范"当前输出端点"字段,取值集合 MUST 至少包含 { USB, BLE },并允许
  未来扩展。
- **FR-007**: 协议 SHOULD 定义"充电状态"字段为**可选**,取值集合 MUST 为**二态**
  `{charging, not_charging}`。固件未实现充电检测、或硬件无法可靠区分"充满 vs 未充"时,
  MUST 通过能力位将整个字段标记为不支持且**不广播**该字段,**MUST NOT** 广播 `full` /
  `unknown` 之类的占位值。对分体键盘,若两侧硬件能力不同,MUST 支持按半声明支持位:
  `capability_bits` 的 bit 5 作为 `has_left_charging`(整板场景时等价于 overall);bit 6
  作为 `has_right_charging`(仅在 `is_split = 1` 时有效,整板时固件 MUST 发 0);UI MUST
  按半分别决定该半充电图标是否渲染,支持"一侧可见、另一侧完全隐藏"的真实不对称场景。
- **FR-008**: 协议 MUST 为所有新增字段提供**变更事件/通知**路径,使 app 无需轮询即可获得
  实时更新。节流规则:**状态性字段**(主机连接、BLE profile 槽位 + open 位、分体在/离线、
  输出端点、充电状态)MUST 在状态变化时立即 notify,不设最小间隔;**数值性字段**(每半或
  整机电量百分比)MUST 满足以下任一条件才 notify——(a)相对上一次已发送值变化 ≥ 1 个百分
  点,或(b)距上一次该字段 notify 已 ≥ 1 秒。KBP 1.0 既有的"snapshot 未变不发"去重规则
  继续适用于所有字段。
- **FR-009**: 协议 MUST 以每字段级的能力位(capability bits)或等价机制声明"该键盘支持哪些
  A 组字段",使 app 能逐项探测。能力位 MUST 至少包含一位 `is_split`,用于声明该键盘是否为
  分体结构;ZMK 参考实现 MUST 将其绑定到 `CONFIG_ZMK_SPLIT`(或等价的 central-role 判定),
  即编译期事实在协议层的直接映射。
- **FR-010**: `protocol/CHANGELOG.md` 与 `protocol/README.md` MUST 更新至 1.1,并保留对
  1.0 的向后兼容说明;`protocol/VERSION` MUST 升级至 `1.1.0`。

**一致性套件(`conformance/`)**

- **FR-011**: 一致性清单 MUST 新增针对 A 组每个字段的自测条目,包括字段存在性、字段范围
  检查、以及"不支持时能否正确缺省"的用例。
- **FR-012**: 自测工具 MUST 能在不依赖 app 的情况下,仅连接键盘并输出一份 A 组字段支持矩阵
  (支持哪些、不支持哪些、异常值情况)。自测工具 MUST 作为**跨平台 CLI** 交付,在
  **macOS、Linux、Windows** 三个平台上均可运行,实现 MUST 与 macOS app 的 CoreBluetooth
  代码解耦(建议采用 Python + bleak 或等价的跨平台 BLE 库,但协议规范不绑定具体实现栈)。

**macOS 应用(`app/macos/`)**

- **FR-013**: app 的菜单栏/悬浮面板 MUST 新增一张"连接与电量"卡片,内容按字段级能力探测
  显示,未支持字段 MUST 不占位。
- **FR-014**: app MUST 以**事件驱动**方式接收上述新增字段(不采用固定周期轮询),且 MUST
  **不**主动做兜底 polling READ;字段级"实时 vs 陈旧"兜底由 FR-015 的 3 秒无 notify 自动
  降级 + BLE 断连事件立即降级承担,与宪章 Principle IV「Observable Degradation Over
  Guessing」一致。
- **FR-015**: app MUST 区分"实时值"与"最后已知值":单个字段若连续 **3 秒**未收到新的
  notify/事件更新(以 app 本地单调时钟为准),或收到键盘断连事件,MUST 立即将该字段标记为
  陈旧状态(例如灰显 + 显示"最后更新于 hh:mm:ss"),不得让用户误以为仍是实时读数。
- **FR-016**: app MUST 对老固件(仅 KBP 1.0)保持当前 1.0 的全部可用功能,不新增强制依赖。
- **FR-017**: 面板上的 profile 槽位视图 MUST 高亮当前槽位,并直观标示其中处于 open(待配对)
  状态的槽位。

**观测与诊断**

- **FR-018**: app MUST 在诊断日志中结构化记录字段级能力探测结果与断连事件,便于用户向键盘
  作者反馈。

### Key Entities *(include if feature involves data)*

- **KeyboardLink(键盘链路)**:描述键盘与主机之间的 BLE 链路,属性包括连接状态、当前
  profile 索引、profile 总数、open 状态、最后一次状态变更时间。
- **BLEProfileSlot(profile 槽位)**:单个 BLE 配对槽位,属性包括索引(1 起)、是否已配对、
  是否当前激活。
- **SplitHalf(分体半边)**:仅对分体键盘有意义,属性包括侧别(左/右)、在/离线、电量
  百分比、可选的充电状态、最后一次状态变更时间。
- **OutputEndpoint(输出端点)**:当前键击去向,取值 USB / BLE / (扩展)。
- **CapabilityMatrix(能力矩阵)**:该键盘声明支持的 A 组字段集合,app 据此按字段级显隐。
  MUST 包含一位 `is_split`(是否分体,由固件按编译期事实如 `CONFIG_ZMK_SPLIT` 声明)以及
  其余 A 组字段的逐项支持位。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 用户从打开菜单栏面板到看清"主机连接 + 当前 profile 槽位"信息,平均耗时
  ≤ 2 秒。
- **SC-002**: 键盘实际状态变化(主机断连 / 切换 profile / 分体某半掉线 / 输出端点切换)到
  面板显示更新之间的延迟,P95 ≤ 2 秒,P50 ≤ 1 秒。
- **SC-003**: 面板显示的每半电量与键盘上报的瞬时电量之间的最大偏差 ≤ 5 个百分点。
- **SC-004**: 老版本 app(KBP 1.0)连接本次升级后的固件,或新版本 app 连接老固件,均能正常
  运行,**崩溃率 = 0**;新字段在不支持的一端表现为"隐藏"而非错误。
- **SC-005**: 一致性自测工具运行一轮(连接 + 探测 + 下线)在 60 秒内完成,并输出覆盖 A 组
  全部字段的支持矩阵。
- **SC-006**: 当键盘硬件不支持"充电状态"时,面板**不出现**该字段的占位,100% 不出现误导
  性的"未充电"展示。
- **SC-007**: 对一把参考分体键盘执行"主机断连 → 重连 → 切换 profile → 切换输出端点 →
  左半掉线 → 恢复"完整剧本,面板展示的每一步都与键盘真实状态保持一致(0 次人工介入即可
  通过)。

## Assumptions

- A 组指标以 **KBP 1.1 MINOR** 增量方式交付,**不破坏** KBP 1.0 的任何既有行为;需要 MAJOR
  破坏性改动的议题不在本 feature 范围内。
- 固件参考实现以 **ZMK** 为准(central/peripheral、profile、HID 指示器、battery/peripheral
  battery 事件等),其他固件栈(QMK、KMK 等)的适配不在本 feature 范围,但协议规范 MUST 保持
  固件无关。
- 平台范围:**macOS app** 为本期交付目标(Windows / Linux app 顺延,不在本 feature 范围);
  **一致性自测 CLI** 需在 macOS / Linux / Windows 三平台均可运行(协议本身与 OS 无关)。
- "充电状态"字段作为**可选硬件相关项**接入,不作为协议合规的强制项;大多数现有板将不实现
  该字段。
- 用户授予 macOS 蓝牙权限、键盘已完成一次性配对;首次配对/权限引导流程沿用现有逻辑,**不
  在本 feature 范围**。
- 协议的权威版本号在 `protocol/VERSION`,一致性清单在 `conformance/`;本 feature 的协议改动
  MUST 走 `protocol/CHANGELOG.md` 的既有流程。
- "WPM / 打字统计 / 层栈 / RGB / RSSI / 运行时长"等 B/C/D 组指标**不在本 feature 范围**,
  各自将在后续 feature 中单独规范。
- app 对 KBP 1.1 新增字段**不做**主动兜底 polling READ;链路级字段陈旧由 FR-015 的被动
  stale 检测承担(事件驱动 + 3 秒无 notify 自动降级 + 断连事件立即降级),符合宪章
  Principle IV。协议端固件只负责按节流规则 notify,主机端不主动再 READ 已订阅的 1.1
  characteristic。
