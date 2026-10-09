# Contract: macOS 应用「连接与电量」卡片(UI 契约)

**Normative** · 本文件固化 macOS 应用新增 UI 的**观察性契约**(即用户/测试可直接验证的
UI 行为)。实施阶段的 `FloatingPanel.swift` + 关联模型 MUST 对齐本契约。本文件**不**约束
具体视图层次或 AppKit API 选择——那是实现自由度。

> **范围**:仅 `app/macos/`。Windows / Linux UI 顺延,不在本 feature 范围。

---

## 1. 卡片级可见性

### 1.1 整张「连接与电量」卡片

| 条件 | UI 行为 |
|------|---------|
| GATT 服务里**没有** `AA440AA2-…` characteristic(KBP 1.0-only 固件) | 卡片**整张隐藏**;FloatingPanel 其他内容(层/修饰键)布局完全不受影响 |
| `AA440AA2-…` 存在 | 卡片显示,行按能力位逐一渲染(见 §2) |
| BLE 未授权 / 蓝牙关闭 | 卡片沿用现有空状态提示(与 KBP 1.0 相同行为),不单独为 1.1 字段渲染占位 |

### 1.2 字段级显隐规则

| capability bit | 字段 | bit = 0 时 UI 行为 |
|----------------|------|-------------------|
| `has_host_connection` | 主机连接状态行 | 整行隐藏 |
| `has_profile` | profile 槽位视图 | 整行隐藏 |
| `has_split_link`(+ is_split) | 左/右半在/离线指示 | 整行隐藏;若 is_split=1 且本 bit=0,仅隐藏在/离线,仍可能有电量行 |
| `has_output_endpoint` | 输出端点行 | 整行隐藏 |
| `has_left_charging` | 左半(或整板)充电图标 | 不渲染该图标(左半电量 % 仍可见) |
| `has_right_charging` | 右半充电图标 | 不渲染该图标(右半电量 % 仍可见);**要求** `is_split = 1`,否则本 bit 必须为 0 |
| `is_split`(推论) | 单电量 vs 左右半电量 | is_split=0 → 单一「整机电量」行;is_split=1 → 「左半 / 右半」两行 |

**不变量 U-1**:字段 bit = 0 时 UI MUST **完全不占位**(无灰显条、无"—"、无"不支持"文案)。
**不变量 U-2**:bit 翻转从 1 → 0 时(例如热重连后固件声明变化),UI MUST 在该特征下一次 notify 到达的同一渲染循环内更新。

---

## 2. 行与子控件的渲染

### 2.1 主机连接行

- 视觉:圆点(绿 = 已连接 / 灰 = 未连接)+ 文案 "已连接" / "未连接"。
- 当 `host_state.last_disconnect_reason ≠ unknown` 且 connected = 0 → 文案追加括号 "(超时)" 或 "(主动断开)"。
- 陈旧状态(§3)时圆点与文案均 50% 透明度 + 右侧 "最后更新 hh:mm:ss"。

### 2.2 Profile 槽位视图

- 视觉:n 个圆形徽标(n = profile_max_slots),水平排列,索引居中。
- 当前 index 的徽标:**粗边框 + 填充**;其他:**细边框 + 空心**。
- `profile_open = 1` 的徽标:加虚线边框 + 右上角 "待配对" 小字(或 i18n 字符串)。
- Click 行为:**只读显示**,**不**提供"切换 profile"按钮(本期不支持写回键盘,FR-013 的"显示"职责)。

### 2.3 分体在/离线行(仅 is_split = 1 且 has_split_link = 1)

- 视觉:左右两个标签 "左 / 右",各带状态点(绿 = online / 红 = offline)。
- offline 时:红点 + 文案 "离线" + 该半电量数字固定在最后已知值 + 时间戳(IV-S2 的要求)。

### 2.4 电量行

| 情形 | 渲染 |
|------|------|
| is_split = 0 | 单一横向条 + 数字百分比 |
| is_split = 1 | 两条横向条(左 / 右),左右并排 |
| `percent = 255`(sentinel) | 条形体灰色 + 文案 "读取失败";**不**显示具体数字 |
| 支持充电(`has_left_charging = 1`)且 `charging_flags.bit 0 = 1` | 左侧(或整板)电量条右上角显示闪电图标 |
| 支持充电(`has_right_charging = 1`)且 `charging_flags.bit 1 = 1` | 右侧电量条右上角显示闪电图标;**要求** `is_split = 1` |
| 两侧硬件能力不同(例如 `has_left_charging = 1 && has_right_charging = 0`) | 只在支持侧渲染图标,另一侧完全不出现(U-1 的按半版本) |

**不变量 U-3**:电量条的填充颜色/长度 **MUST** 对应**原始**百分比值;展示层允许 3 秒滑动平均但 MUST 不影响数字判读(SC-003)。

### 2.5 输出端点行

- 视觉:单行文案 "输出:USB" / "输出:BLE"。
- 保留 raw code(≥ 3)时:显示 "输出:未知(0x0n)"。

---

## 3. 陈旧 vs 实时的视觉区分(FR-015)

### 3.1 判定规则

- 每字段维护一个"最后一次 notify 时间"(单调时钟,`CFAbsoluteTimeGetCurrent()`)。
- 后台调度 **1 Hz** 检查:若 `now - lastNotifyAt ≥ 3.0` 秒 → 字段陈旧。
- BLE 断连事件(`centralManager:didDisconnectPeripheral:`)→ **所有** 字段立即陈旧。
- 新 notify 到达 → 字段立即恢复实时。

### 3.2 视觉规则

| 状态 | 字段样式 |
|------|---------|
| 实时(live) | 正常字体 + 100% 不透明 + **无**时间戳 |
| 陈旧(stale) | 50% 不透明 + 字段右侧或下方附 "最后更新 hh:mm:ss"(本地时区,24h 格式) |

**不变量 U-4**:陈旧视觉 MUST 一眼能看出(不能靠细微色调差异);色盲友好:灰度区分优先,颜色次之。

---

## 4. 与 KBP 1.0 UI 的共存

- 现有层/修饰键显示(KeyboardStatus)**零改动**,一切 KBP 1.0 UI 行为保留。
- 新「连接与电量」卡片在 FloatingPanel 中位于**层/修饰键区块下方**(实施阶段可微调,但 MUST 不打断现有视觉习惯)。
- 菜单栏图标与行为**无改动**:新字段只影响 FloatingPanel,菜单栏保持当前 KBP 1.0 的最小呈现。

---

## 5. 诊断日志钩子(FR-018)

- 实施阶段的 AppDelegate(或新建的 `DiagnosticsLogger.swift`)MUST 用 `os.Logger`(subsystem = `com.keybeacon.app`)发出以下事件(category 后缀):
  - `capability.discovered`(新设备连接后首次 CapabilityMatrix 解析成功)
  - `capability.inconsistent`(IV-C1 触发)
  - `capability.mutated`(§CapabilityMatrix 状态转换中的热变化)
  - `profile.out_of_range`(IV-P1 触发)
  - `battery.length_mismatch` / `battery.out_of_range`
  - `staleness.field_stale` / `staleness.field_live`(每字段每次跨阈值各发一次)
  - `connection.state_changed`(host_state.connected 翻转)
- 日志格式:使用 OSLog 的 `%{public}` 标注使字段**对用户可见**(非敏感),便于 Console.app 过滤。

---

## 6. 测试契约(手工 + XCTest)

### 6.1 XCTest(非 UI 测试)

- `CapabilityMatrixTests`:覆盖 §3.2 全部 bit 组合、IV-C1、IV-C2。
- `ConnectivityStatusTests`:覆盖 payload 短/长/边界、profile 越界、reserved 位 ≠ 0。
- `BatteryStatusTests`:覆盖 is_split=0/1 的长度、sentinel 255、101–254 保留值。
- `StalenessTrackerTests`:覆盖 3 秒阈值、断连触发、notify 恢复、单调时钟方向。

### 6.2 手工 UI 测试(quickstart.md 中)

- "切 profile 面板跟随 ≤ 1s"、"断连 3 秒后灰显 + 时间戳"、"分体一侧掉线不覆盖电量"、"充电字段隐藏不占位"、"端点切换 ≤ 1s" 五个核心剧本。

---

## 7. 不变量汇总

| ID | 不变量 | 对应 FR |
|----|--------|---------|
| U-1 | capability bit = 0 的字段 UI 完全不占位 | FR-013, SC-006 |
| U-2 | bit 翻转后 UI 下一个渲染循环更新 | FR-013 |
| U-3 | 电量条数值等于协议端原始值(平滑仅视觉) | FR-005, SC-003 |
| U-4 | 陈旧状态在视觉上一眼可辨 | FR-015 |
| U-5 | 卡片对 KBP 1.0 固件整张隐藏 | FR-016, SC-004 |
