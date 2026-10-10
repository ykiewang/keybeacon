# Contract: KBP 1.1 Connectivity & Power(wire 契约)

**Normative** · 本文件是 KBP 1.1 新增两个 BLE characteristic 的**权威字节级契约**。
实施阶段 `protocol/README.md` 的 §14 新章节 MUST 与本文一字一句对齐,**本文件先于**
`protocol/README.md`,`/speckit-implement` 时再把两者同步。

> **术语沿用**:MUST / SHOULD / MAY 按 RFC 2119。生产者 = 键盘固件;消费者 = 主机 app
> 或自测 CLI。

---

## 1. 范围与版本

- **KBP MAJOR**:1(service UUID `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` **不变**)。
- **KBP MINOR**:新增至 **1.1**。
- **破坏性**:无。1.0 既有 characteristic `AA440AA1-…` **零改动**(§protocol/README.md §4 的 payload 布局不变)。
- **协议向后兼容性保证**:
  - KBP 1.0 主机(只订阅 `AA440AA1-…`)连 KBP 1.1 键盘 → 1.1 新特征不被订阅,固件不发 notify,行为完全退化为 1.0。
  - KBP 1.1 主机连 KBP 1.0 键盘 → GATT 服务发现找不到新特征,主机 MUST **整体隐藏**新 UI,其他行为与 1.0 相同。

---

## 2. 两个新 Characteristic 概览

| Item | Connectivity characteristic | Battery characteristic |
|------|------------------------------|------------------------|
| UUID | `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` | `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` |
| Properties | `READ` \| `NOTIFY` | `READ` \| `NOTIFY` |
| Descriptor | Client Characteristic Configuration(CCC,`0x2902`) | Client Characteristic Configuration(CCC,`0x2902`) |
| Permission | readable | readable |
| 承载 | 所有状态性字段 + capability bits | 整板或分体的电量百分比 |
| notify 节流 | 变即发(状态性) | 变化 ≥ 1 pp **或** 距上次 ≥ 1s(数值性) |
| 可缺省 | 整特征可缺省(表示固件不支持 KBP 1.1 任何可选字段) | 整特征可缺省(表示固件不实现电量上报) |

**生产者 MUST**:两个特征的宿主 primary service 是 KBP 1.0 的同一个
`AA440AA0-F5ED-4C48-84A1-8062D20D3D55`,**不**新增 service。

---

## 3. Connectivity characteristic payload

### 3.1 布局(小端序,**固定长度 ≥ 7 字节**)

| Offset | Size | Field               | 范围 / 编码 |
|--------|------|---------------------|-------------|
| `[0]`  | 1    | `capability_bits`   | uint8,每位含义见 §3.2 |
| `[1]`  | 1    | `host_state`        | bit 0: `connected`;bits 1–2: `last_disconnect_reason`(0 unknown / 1 explicit / 2 timeout / 3 reserved);bits 3–7 reserved(1.1 固件 MUST 发 0) |
| `[2]`  | 1    | `profile_index`     | bits 0–6: 1-based 索引(0 = 字段不适用);bit 7: `profile_open`(1 = open 待配对) |
| `[3]`  | 1    | `profile_max_slots` | uint8,固件声明的最大槽位数(0 = 字段不适用) |
| `[4]`  | 1    | `split_link_flags`  | bit 0: left_online;bit 1: right_online;bits 2–7 reserved(1.1 MUST 发 0)|
| `[5]`  | 1    | `output_endpoint`   | 0 = unknown / 1 = USB / 2 = BLE / 3–255 reserved(保留未来扩展) |
| `[6]`  | 1    | `charging_flags`    | bit 0: left_charging(整板时为 overall,**要求** `has_left_charging = 1`);bit 1: right_charging(**要求** `is_split = 1` 且 `has_right_charging = 1`,整板时固件 MUST 发 0);bits 2–7 reserved |
| `[7..N]` | ≥ 0 | reserved trailing bytes | 未来 MINOR 的追加字节;**生产者**在 1.1 发 0 字节(即 payload 恰为 7 字节);**消费者** MUST 忽略尾部 |

### 3.2 `capability_bits`(byte 0)

| Bit | Mask | Name                 | 含义 |
|-----|------|----------------------|------|
| 0   | 0x01 | `is_split`           | 该键盘是分体(ZMK 参考实现绑定 `CONFIG_ZMK_SPLIT`) |
| 1   | 0x02 | `has_host_connection`| `host_state` 字段有效 |
| 2   | 0x04 | `has_profile`        | `profile_index` + `profile_max_slots` 有效 |
| 3   | 0x08 | `has_split_link`     | `split_link_flags` 有效;**要求** bit 0 = 1 |
| 4   | 0x10 | `has_output_endpoint`| `output_endpoint` 有效 |
| 5   | 0x20 | `has_left_charging`  | `charging_flags.bit 0` 有效(整板时为 overall) |
| 6   | 0x40 | `has_right_charging` | `charging_flags.bit 1` 有效;**要求** bit 0 = 1(`is_split = 1`),整板时固件 MUST 发 0 |
| 7   | 0x80 | reserved             | 1.1 固件 MUST 发 0 |

### 3.3 不变量(生产者 MUST 保证)

- **P-C1**:若 `has_split_link = 1`,则 `is_split = 1`。
- **P-C2**:对任一能力位 = 0 的字段,固件 MAY 填 0 字节;消费者 MUST 忽略该字段的具体值。
- **P-C3**:`profile_index` 的 bits 0–6 ≤ `profile_max_slots`(索引不得越界)。
- **P-C4**:1.1 固件 MUST 把 reserved 位(byte 1 bits 3–7、byte 2 bit 7 已占用、byte 4 bits 2–7、byte 6 bits 2–7、byte 0 bit 7、byte 7+)全部发 0。
- **P-C5**:若 `has_right_charging = 1`,则 `has_left_charging = 1` **且** `is_split = 1`;整板键盘(`is_split = 0`)下 `has_right_charging` MUST = 0 且 `charging_flags.bit 1` MUST = 0。

### 3.4 消费者规则(主机 MUST)

- **C-C1**:payload 长度 **< 7 字节** → 整条丢弃,记一次结构化诊断日志,**不**更新 UI。
- **C-C2**:payload 长度 **≥ 7 字节** → 消费 byte 0..6,忽略 byte 7+(保证 MINOR 向上兼容)。
- **C-C3**:若 `capability_bits.has_split_link = 1` 但 `is_split = 0`,主机 MUST 把 `has_split_link` 当作 0(视为固件 bug),记一次 `capability.inconsistent`。
- **C-C4**:若 `profile_index` 的 bits 0–6 > `profile_max_slots`,主机 MUST 把 UI 显示的 index 钳制在 `profile_max_slots` 并记一次 `profile.out_of_range`。
- **C-C5**:对 `output_endpoint` 的 3–255 保留值,主机 MUST 显示为 "未知端点(0x__)" 而非崩溃。
- **C-C6**:若 `has_right_charging = 1` 但 `is_split = 0`,主机 MUST 把 `has_right_charging` 当作 0(视为固件 bug),记一次 `capability.inconsistent`;右半充电图标 MUST 不渲染。
- **C-C7**:若 `has_left_charging = 0` 但 `charging_flags.bit 0` 非 0,主机 MUST 忽略该 bit 值并记一次 `capability.inconsistent`(bit 1 同理)。

### 3.5 notify 节流(生产者 MUST)

- 状态性字段的任一比特翻转或 enum 值变化 → **立即** notify 当前 snapshot。
- 继承 KBP 1.0 §5 "snapshot 未变不发" 抑制规则:固件 MUST 在重新计算的 snapshot 与上次发送的 snapshot 字节相等时**抑制**通知。

---

## 4. Battery characteristic payload

### 4.1 布局(小端序,**长度随 is_split**)

| 情形(来自 Connectivity.capability_bits.is_split) | payload 长度 | 字节 |
|------|------|------|
| `is_split = 0`(整板) | **1 byte** | `[0]` = `overall_battery_percent`(uint8) |
| `is_split = 1`(分体) | **2 bytes** | `[0]` = `left_battery_percent`,`[1]` = `right_battery_percent`(各 uint8) |

### 4.2 电量取值(uint8 编码)

| 值范围 | 含义 |
|------|------|
| `0..100` | 正常百分比 |
| `101..254` | 保留 |
| `255` | sentinel:读取失败 / 临时不可用(例如 I²C 短暂失联) |

### 4.3 不变量(生产者 MUST 保证)

- **P-B1**:payload 长度与 `is_split` 严格一致(不发 0 字节、不发 3 字节以上)。
- **P-B2**:协议端 **透传原始读数**;MUST **不**在固件做滑动平均或平滑,防止把"读取瞬时失败"洗成"正常低电"。
- **P-B3**:固件若整体无法上报电量 → 整个 Battery characteristic MUST 不实现(GATT 发现时就不出现)。

### 4.4 消费者规则(主机 MUST)

- **C-B1**:若 Connectivity.capability_bits.is_split = 0 而 Battery payload ≠ 1 字节 → 丢弃并记 `battery.length_mismatch`。
- **C-B2**:若 is_split = 1 而 payload ≠ 2 字节 → 丢弃并记 `battery.length_mismatch`。
- **C-B3**:字节值 ∈ [0, 100] → 显示百分比;= 255 → 显示 "读取失败";101–254 → 显示 "读取失败" 并记 `battery.out_of_range`。
- **C-B4**:主机 MAY 对渲染值做 ≤ 3 秒的滑动平均作为抖动平滑,**MUST NOT** 影响 SC-003 判定(即诊断日志中保留原始值)。

### 4.5 notify 节流(生产者 MUST)

数值性字段节流规则,**或**关系触发:

- 条件 A:相对上一次已发送的字节值变化 ≥ 1(即 ≥ 1 个百分点)。
- 条件 B:距上一次该字段 notify 已 ≥ 1 秒。

**A ∨ B** 成立 → notify。继承 KBP 1.0 §5 的"snapshot 未变不发"规则(即原始字节完全相等时不触发)。

---

## 5. 发现与订阅(消费者流程)

- 服务发现仍按 KBP 1.0 §2 规则:通过 `retrieveConnectedPeripherals(withServices: [HID, KBPService])` 枚举已连接外设,GATT 中确认 `AA440AA0-…` 服务存在。
- 服务存在后,消费者 MUST 请求发现 service 下**所有** characteristics,根据各 UUID 的**存在性**判定键盘声称支持的 KBP MINOR:
  - 只找到 `AA440AA1-…` → 1.0 only;消费者 MUST **不**展示 1.1 UI。
  - 找到 `AA440AA1-…` 和 `AA440AA2-…` → 支持 1.1 Connectivity 字段;再按 `AA440AA3-…` 是否存在决定电量 UI。
  - 找到 `AA2` 但 `AA1` 缺失 → 异常,主机 MUST 记 `discovery.anomaly` 并按 1.0-only 行为处理(永不裸信任 1.1 字段)。
- 消费者 MUST 对已订阅的每个新特征在重连时**重新** READ + CCC subscribe。

---

## 6. 版本信号与升级路径

- 服务 UUID 不变意味着 KBP 1.0/1.1 **wire 可识别性等价**;MINOR 判定靠 characteristic 存在性。
- 若未来需要 KBP 1.2+,新字段继续按本契约的"**追加 characteristic** 或 **在 Connectivity 的 reserved bytes 中追加**"策略推进(§protocol/README.md §9 MINOR 规则)。
- 任何涉及重新解释 byte 位置 / 修改 UUID 的变更一律 **MAJOR**,MUST 走 service UUID 替换路径。

---

## 7. 与 KBP 1.0 §10 一致性清单的扩展

本契约对应的新增一致性条目(在 `conformance/checklist.md` 实施阶段落实为 C7–C12,见
`contracts/conformance-cli.md`):

- **C7**:`AA440AA2-…` characteristic 存在时,properties = `READ`+`NOTIFY`,带 CCC。
- **C8**:Connectivity READ 返回 ≥ 7 字节,各字段符合 §3 布局与不变量 P-C1..P-C4。
- **C9**:`AA440AA3-…` characteristic 存在时,properties = `READ`+`NOTIFY`,带 CCC,且 payload 长度与 is_split 一致。
- **C10**:状态性字段变化触发 notify、snapshot 不变抑制。
- **C11**:数值性字段节流符合 §4.5 规则(≥ 1 pp 或 ≥ 1s,**或** 关系)。
- **C12**:新特征仅在分体键盘的 central 角色实现(协议 §8.4 的 "feature 仅从 central 暴露" 规则延伸到 1.1)。

---

## 8. 固件参考映射(非规范性,ZMK)

| KBP 1.1 字段 | ZMK 参考源 |
|-------------|-----------|
| `is_split` 位 | `IS_ENABLED(CONFIG_ZMK_SPLIT) && IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)` |
| `host_state.connected` | `zmk_ble_active_profile_is_connected()` + 订阅 `zmk_ble_active_profile_changed` |
| `profile_index` + `profile_open` + `profile_max_slots` | `zmk_ble_active_profile_index()`、`zmk_ble_active_profile_is_open()`、`ZMK_BLE_PROFILE_COUNT` |
| `split_link_flags` | 订阅 `zmk_split_bt_peripheral_status_changed`;读 `zmk_split_bt_peripherals_connected()` |
| `output_endpoint` | 订阅 `zmk_endpoint_changed`;读 `zmk_endpoints_selected()`(USB_HID → 1,BLE → 2) |
| `charging_flags` | 板级 charger GPIO(多数开发板不实现) |
| `overall_battery` / `left_battery` / `right_battery` | 订阅 `zmk_battery_state_changed` + `zmk_peripheral_battery_state_changed`;central 侧聚合 |

API 名随 ZMK 版本可能有变;实施阶段(`zmk-keybeacon` 外部模块)**MUST** 核对当前 ZMK main 分支的实际符号。
