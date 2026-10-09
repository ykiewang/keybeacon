# Data Model: 连接与电量指标(KBP 1.1)

**Scope**: 本 feature 的域模型描述,**不含** Swift / Python 具体实现;字段名、类型、取值域、
不变量、状态转换都在这里固化。协议层以 BLE 字节为契约;app 层以 Swift struct 为契约;两
端通过本文件对齐。

> 引用约定:`FR-XXX`、`SC-XXX`、`§N` 分别引用 spec.md 的 Functional Requirement、
> Success Criteria,以及 `protocol/README.md` 的章节号。

---

## 实体总览

```
┌──────────────────────┐    exposes    ┌───────────────────────┐
│ KeyboardLink         │◄──────────────│ CapabilityMatrix      │
│ (host↔keyboard link) │               │ (feature-level flags) │
└──────────────────────┘               └───────────────────────┘
          │ 1
          │
          │ 1
┌─────────▼──────────┐  (optional, only if is_split)  ┌───────────────┐
│ BLEProfileSlots    │                                 │ SplitHalf     │
│ (slot index/max/   │                                 │ left + right  │
│  open flag)        │                                 └───────────────┘
└────────────────────┘                                       │ battery
                                                              │ online
                                                              │ charging
┌──────────────────────┐                              ┌───────▼───────┐
│ OutputEndpoint       │                              │ BatteryReading│
│ { usb, ble, other }  │                              │ (0..100 or    │
└──────────────────────┘                              │  sentinel 255)│
                                                      └───────────────┘
```

---

## 1. CapabilityMatrix

**含义**:固件在 Connectivity 特征的 `capability_bits` 字节中声明的字段级能力集合。
app **MUST** 在订阅 Connectivity 特征的第一次 READ 后立即解析,并以此决定其他字段的
解析与渲染是否生效。

### 字段

| Field          | Type   | 来源(bit) | 可空 | 含义 |
|----------------|--------|------------|------|------|
| `isSplit`      | Bool   | bit 0      | 否   | 该键盘是否为分体结构;ZMK 参考实现绑定 `CONFIG_ZMK_SPLIT`(FR-009) |
| `hasHostConnection` | Bool | bit 1   | 否   | 主机连接状态字段(`host_state.connected` + 断连来源)有效 |
| `hasProfile`   | Bool   | bit 2      | 否   | BLE profile 字段(`profile_index` + `profile_max_slots` + `profile_open`)有效 |
| `hasSplitLink` | Bool   | bit 3      | 否   | 分体左右半在/离线字段(`split_link_flags`)有效。**不变量**:`hasSplitLink → isSplit`(FR-004) |
| `hasOutputEndpoint` | Bool | bit 4   | 否   | 输出端点字段(`output_endpoint`)有效 |
| `hasLeftCharging`  | Bool | bit 5    | 否   | 左半(或整板)充电位(`charging_flags.bit 0`)有效;**取值集合二态**(FR-007) |
| `hasRightCharging` | Bool | bit 6    | 否   | 右半充电位(`charging_flags.bit 1`)有效;**不变量**:`hasRightCharging → (isSplit ∧ hasLeftCharging)`(FR-007) |
| `_reserved7`   | Bool   | bit 7      | 否   | 1.1 固件 MUST 发 0;app MUST 忽略 |

### 不变量 & 校验规则

- **IV-C1**(`hasSplitLink → isSplit`):若 `hasSplitLink = 1` 而 `isSplit = 0`,app MUST 视为固件 bug,**丢弃** `hasSplitLink` 并记一次 `capability.inconsistent` 诊断日志。
- **IV-C2**(未知 bit 容忍):app MUST 对 `_reserved7` 位的任意值不报错,确保下一个 MINOR 可追加能力。
- **IV-C3**(`hasRightCharging → isSplit ∧ hasLeftCharging`):若 `hasRightCharging = 1` 而 `isSplit = 0` 或 `hasLeftCharging = 0`,app MUST 视为固件 bug,**丢弃** `hasRightCharging` 并记一次 `capability.inconsistent`。

### 状态转换

CapabilityMatrix 对一个已连接的键盘**生命周期恒定**(直到重新连接);每次 Connectivity
特征 notify 中 app MUST 重新读 byte 0 并与上一次比对,**不一致**则记一次
`capability.mutated` 诊断日志但仍以**最新**值为准(容忍固件热更新 keymap 导致的能力变化)。

---

## 2. KeyboardLink

**含义**:键盘与主机之间的 BLE 链路态,聚合主机连接位、断连来源与"实时 vs 陈旧"元数据。

### 字段

| Field              | Type         | 来源 | 可空 | 含义 |
|--------------------|--------------|------|------|------|
| `connected`        | Bool         | Connectivity byte[1] bit 0 | 否 | 1 = 已连接 / 0 = 未连接 |
| `lastDisconnectReason` | enum `{ unknown, explicit, timeout }` | byte[1] bits 1–2 | 否 | 0=未知 / 1=主动 / 2=超时 / 3=保留 |
| `lastNotifyAt`     | monotonic timestamp | app 本地 | 否 | 本字段最近一次 notify 的本地单调时钟值;用于 FR-015 staleness 判定 |
| `isStale`          | Bool(派生)  | app 本地 | 否 | 派生字段:`now - lastNotifyAt >= 3.0` 时为 true;断连事件也 override 为 true |

### 不变量 & 校验规则

- **IV-K1**:当 `CapabilityMatrix.hasHostConnection = 0` 时,app MUST **忽略** `connected` / `lastDisconnectReason`,并且 UI MUST 不渲染该行。
- **IV-K2**:byte[1] 的 bits 3–7 由 1.1 固件声明为 0;app 不解析,但 reserved 位的其他值不触发错误。

### 状态转换

```
       ┌──────────┐  host disconnect event   ┌────────────┐
       │          │─────────────────────────►│            │
       │  live    │                          │   stale    │
       │          │◄─────────────────────────│            │
       └──────────┘    new notify arrives    └────────────┘
            ▲                                      │
            └── 3s elapsed since lastNotifyAt ─────┘
```

---

## 3. BLEProfileSlots

**含义**:当前键盘的 BLE 多主机配对槽位视图(ZMK 的 "profile" 概念)。

### 字段

| Field          | Type          | 来源 | 可空 | 含义 |
|----------------|---------------|------|------|------|
| `index`        | UInt8(1–127)  | Connectivity byte[2] bits 0–6 | 否 | 当前激活的槽位索引;**0** 表示"字段不适用" |
| `isOpen`       | Bool          | byte[2] bit 7 | 否 | 当前槽位是否处于 open / 待配对状态 |
| `maxSlots`     | UInt8(1–255)  | Connectivity byte[3] | 否 | 固件声明的最大槽位数;**0** 表示"字段不适用"(应与 index=0 同时发生) |

### 不变量 & 校验规则

- **IV-P1**:`index > maxSlots` 时,app MUST 把 UI 显示的 index **钳制在 `maxSlots`**,并记一次 `profile.out_of_range` 诊断日志(spec Edge Case:profile 索引越界)。
- **IV-P2**:`CapabilityMatrix.hasProfile = 0` 时,UI MUST 完全隐藏 profile 行。

### 状态转换

离散事件:固件按 `zmk_ble_active_profile_changed` 事件更新 index / open;变化即发 notify。

---

## 4. SplitHalf × 2(left + right)

**含义**:分体键盘的单边状态。仅当 `CapabilityMatrix.isSplit = 1` 时存在;整板键盘无此实体。

### 字段

| Field          | Type   | 来源 | 可空 | 含义 |
|----------------|--------|------|------|------|
| `side`         | enum `{ left, right }` | 常量 | 否 | 侧别 |
| `online`       | Bool   | Connectivity byte[4] bit 0 (left) / bit 1 (right) | 否 | 在/离线;**要求** `hasSplitLink = 1` 否则字段不可信 |
| `battery`      | BatteryReading | Battery payload byte[0] (left) / byte[1] (right) | 否 | 见 §5 |
| `charging`     | Bool   | Connectivity byte[6] bit 0 (left/overall) / bit 1 (right) | 否 | 是否充电;**要求** `hasLeftCharging = 1`(左/整板)或 `hasRightCharging = 1`(右)否则该半字段隐藏 |
| `lastNotifyAt` | monotonic timestamp | app 本地 | 否 | 本半字段最近一次 notify 的本地单调时钟 |
| `isStale`      | Bool(派生) | app 本地 | 否 | 规则同 KeyboardLink |

### 不变量 & 校验规则

- **IV-S1**(整板场景):若 `isSplit = 0`,SplitHalf 实体 MUST 完全不出现在 UI;Battery payload 必定为单字节 overall。
- **IV-S2**(半掉线):`online = 0` 时,UI MUST 把该半的 `battery` 标记为"最后已知值 + 时间戳",**MUST NOT** 显示为实时数据。
- **IV-S3**(字段级降级):若该半对应的能力位 = 0(左半看 `hasLeftCharging`、右半看 `hasRightCharging`),该半 `charging` 字段 MUST 从 UI 隐藏,**不显示** "未充电" 占位;两侧硬件能力不同时允许一侧可见、另一侧完全隐藏。

### 状态转换

```
   ┌────────┐  bit toggled    ┌─────────────────────┐
   │ online │────────────────►│ offline (stale shown│
   │        │◄────────────────│  with timestamp)    │
   └────────┘                 └─────────────────────┘
```

---

## 5. BatteryReading

**含义**:电量百分比的单字节表示,整板时 1 份、分体时 2 份。

### 字段

| Field          | Type         | 来源 | 可空 | 含义 |
|----------------|--------------|------|------|------|
| `percent`      | UInt8        | Battery payload | 否 | 0–100 正常值;101–254 保留;**255** = sentinel "读取失败/临时不可用" |
| `displayValue` | 枚举 `{ percent(0..100), unavailable }` | 派生 | 否 | app 层包装:`percent ∈ [0,100]` → `.percent(n)`;`percent = 255` → `.unavailable`;其他保留值一律 `.unavailable` 并记一次 `battery.out_of_range` |

### 不变量 & 校验规则

- **IV-B1**:协议端 **透传原始字节**(spec Edge Case:协议层 MUST 不做平滑)。
- **IV-B2**:app 展示层 **MAY** 做 3 秒滑动平均作为抖动平滑,但 MUST **只影响渲染值**,不影响单测/日志中的原始值与 SC-003 的"±5%"判定。

### 状态转换
无;每次 notify 覆盖上一个 reading。

---

## 6. OutputEndpoint

**含义**:当前键击实际送往的物理/逻辑端点。

### 字段

| Field       | Type                                  | 来源 | 可空 | 含义 |
|-------------|---------------------------------------|------|------|------|
| `endpoint`  | enum `{ unknown, usb, ble, reserved(UInt8) }` | Connectivity byte[5] | 否 | 0=unknown / 1=USB / 2=BLE / ≥3=保留(保留 raw code) |

### 不变量 & 校验规则

- **IV-O1**:`CapabilityMatrix.hasOutputEndpoint = 0` 时,UI MUST 隐藏输出端点行,**不显示** USB 或 BLE 默认值。
- **IV-O2**:app 对 `reserved(n)` 值 MUST 显示为 "未知端点 (0x0n)" 而非崩溃;支持未来 MINOR 扩展(例如 USB-C PD passthrough)。

---

## 7. ConnectivityStatus(聚合值)

**含义**:对 Connectivity 特征单次 payload 的 Swift 层解析结果——把 7+ 字节的字节数组
翻译为一个值类型。本质是 `(CapabilityMatrix, KeyboardLink, BLEProfileSlots, splitFlags, OutputEndpoint, chargingFlags)` 的元组视图。

### 字段

| Field         | Type               | 含义 |
|---------------|--------------------|------|
| `capability`  | CapabilityMatrix   | byte[0] |
| `link`        | KeyboardLink(除 timestamp) | byte[1] |
| `profile`     | BLEProfileSlots    | byte[2..3] |
| `splitFlags`  | `(leftOnline: Bool, rightOnline: Bool)` | byte[4],仅 `hasSplitLink=1` 时有效 |
| `output`      | OutputEndpoint     | byte[5] |
| `chargingFlags` | `(leftCharging: Bool, rightCharging: Bool)` | byte[6],左半/整板位(bit 0)仅 `hasLeftCharging=1` 时有效;右半位(bit 1)仅 `hasRightCharging=1` 时有效(整板时固件 MUST 发 0) |

### 不变量 & 校验规则

- **IV-CS1**:raw payload 长度 < 7 字节 → **MUST** 整体丢弃并记一次 `connectivity.short_payload` 诊断日志(类比 KBP 1.0 §4 "载荷 ≥ 2 字节")。
- **IV-CS2**:raw payload 长度 > 7 字节 → **MUST** 忽略尾部,保留当前字段;支持下一个 MINOR 追加。

---

## 8. BatteryStatus(聚合值)

**含义**:对 Battery 特征单次 payload 的解析结果。

### 字段

| Field              | Type                                          | 含义 |
|--------------------|-----------------------------------------------|------|
| `kind`             | enum `{ overall(BatteryReading), split(left: BatteryReading, right: BatteryReading) }` | 由 CapabilityMatrix.isSplit 决定 |

### 不变量 & 校验规则

- **IV-BS1**:`isSplit = 0` 要求 Battery payload 长度 = 1;长度 ≠ 1 → 丢弃并记 `battery.length_mismatch`。
- **IV-BS2**:`isSplit = 1` 要求 Battery payload 长度 = 2;长度 ≠ 2 → 丢弃并记 `battery.length_mismatch`。
- **IV-BS3**:Battery 特征本身若不存在(即固件未实现本特征),整板/分体电量 UI **整列隐藏**,与"字段 unavailable sentinel"不同——前者是无特征,后者是有特征但读取失败。

---

## 9. 跨实体不变量汇总

| ID | 不变量 | 关联 FR / Edge Case |
|----|--------|---------------------|
| IV-X1 | GATT 服务里没有 `AA440AA2-…` 特征 → app 整个「连接与电量」卡片 **MUST** 隐藏 | FR-013, FR-016, SC-004 |
| IV-X2 | GATT 服务里没有 `AA440AA3-…` 特征 → 电量区块隐藏,其他 Connectivity 字段按 capability bits 照常显示 | FR-005, FR-013 |
| IV-X3 | 任一字段最近 ≥ 3s 无 notify → UI 对该字段降级为陈旧;收到新 notify 立即恢复 | FR-015 |
| IV-X4 | BLE 断连事件 → 所有字段立即降级为陈旧,保留"最后已知值" | FR-015, Edge Case "断连后残留" |
| IV-X5 | `capability_bits` 中声明 = 0 的字段 → UI 完全隐藏,**不占位** | FR-013, SC-006 |
| IV-X6 | 老 app 连新固件,或新 app 连老固件 → 零崩溃,行为降级清晰 | SC-004 |

---

## 10. 名字与术语的标准化

| 规范术语 | 禁用的同义词 | 来源 |
|---------|------------|------|
| `profile`(ZMK 术语) | "channel"、"slot" | §3,ZMK 社区惯例 |
| `is_split` | "has_peripheral"、"is_dual" | FR-009 / Clarifications Q2 |
| `output_endpoint` | "output_type"、"sink" | FR-006 |
| `host_state.connected` | "paired"、"linked" | FR-002 |
| `is stale`(陈旧) | "offline"、"disconnected"(易混淆) | FR-015 |
