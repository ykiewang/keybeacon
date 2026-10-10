# Phase 0 Research: 连接与电量指标(KBP 1.1)

**Scope**: 把 spec.md 中所有可能被标注为 `NEEDS CLARIFICATION` 的技术决策**提前锁死**。
由于 `/speckit-clarify` 阶段已经消化了 5 个高影响问题,本文件覆盖其余"显而易见但需要
留痕"的决策,以及后续 `/speckit-tasks` 阶段依赖的技术选型依据。

---

## 1. KBP 1.1 的协议演进策略

### Decision
采用 **MINOR 版本号 + 保持 service UUID 不变 + 新增可选 characteristics** 的组合,严格按
KBP 1.0 §9 的 MINOR 规则交付。KBP 1.0 的既有特征(`AA440AA1-…`)**零改动**,所有 A 组
字段通过**新增**两个独立 characteristic 承载。

### Rationale
- §9 明确规定 MINOR 允许"追加保留尾部字节,或添加新的可选 characteristic/descriptor,**service UUID 不变**"。
- 老 app(KBP 1.0)订阅 `AA440AA1-…`,对新特征视而不见,行为完全不变——直接满足 SC-004 的"崩溃率 = 0 / 新字段表现为隐藏"。
- 若选择"把 A 组字段追加到既有特征的尾部字节",会违反 FR-008 的差异化节流要求(状态性字段立即发 vs 数值性字段节流);两个独立 characteristic 让各自的 notify 规则天然解耦。

### Alternatives Considered
- **A1. 单 characteristic 追加尾部字节**:符合 §9 MINOR 规则,但会迫使状态性与数值性字段共享同一 notify 周期,违反 FR-008 节流差异;且 UTF-8 `layer_name` 可变长度处于 payload 中段会让尾部字节难以稳定定位。**拒绝**。
- **A2. 新 service UUID(整个新 primary service)**:语义上更"干净"但触发了 §9 的 MAJOR 规则,会给老 app 发出"不支持"信号——违反 FR-016 和 SC-004。**拒绝**。
- **A3. 一特征一字段(6 个独立 characteristics)**:节流最灵活但 ATT 流量 overhead 显著,CCC 数翻倍,代码复杂度骤增,对手工自测不友好。**拒绝**。

---

## 2. 两个新特征的分工

### Decision
- **`Connectivity` 特征**(`AA440AA2-F5ED-4C48-84A1-8062D20D3D55`,`READ`+`NOTIFY`+CCC):承载**所有状态性字段**——capability bits、主机连接状态与断连来源、BLE profile(索引+总槽位+open 位)、分体在/离线、输出端点、充电状态。节流规则:**变即发**(FR-008)。
- **`Battery` 特征**(`AA440AA3-F5ED-4C48-84A1-8062D20D3D55`,`READ`+`NOTIFY`+CCC):承载**数值性字段**——整机或左/右半电量百分比。节流规则:**变化 ≥ 1 pp 或 ≥ 1s** 之一满足(FR-008)。

### Rationale
- 状态性(低频、离散事件)与数值性(高频、连续量)天然分离,各自独享 CCC,互不干扰。
- 现有 KBP 1.0 已有 1 个 characteristic,再加 2 个仍落在"少量 characteristic"量级,ATT MTU 下的 handle 开销可忽略。
- 自测工具只需枚举这两个 UUID 的存在性即可判定键盘是否声称支持 1.1,无需额外的 version-advertise 字段。

### Alternatives Considered
- **B1. 把充电状态单独成第三个特征**:充电是极低频的状态事件,与 Connectivity 的其他状态字段天然同族,单拆没有收益。**拒绝**。
- **B2. 用一个 characteristic 分 payload 类型字节区分**:会把 TLV 复杂度塞进 payload head,老设备和新设备的解析分叉成本更高。**拒绝**。

---

## 3. UUID 分配

### Decision
- `Connectivity` characteristic UUID: `AA440AA2-F5ED-4C48-84A1-8062D20D3D55`
- `Battery` characteristic UUID:      `AA440AA3-F5ED-4C48-84A1-8062D20D3D55`

### Rationale
- 延续 `AA440AAx-F5ED-4C48-84A1-8062D20D3D55` 命名家族(§familySuffix 已在 `KBPCompatibility.swift:34` 定义),使 UUID 自身即可暗示"同一协议家族的 KBP 1.x 可选扩展"。
- `AA2`/`AA3` 为下一步的 1.2 / 1.3 字段预留 `AA4`/`AA5`。

### Alternatives Considered
- **使用完全随机的 base-UUID**:破坏家族前缀的可读性,无技术收益。**拒绝**。

---

## 4. Capability Bits 的具体位分配

### Decision
在 `Connectivity` payload 的 **byte 0**(`capability_bits`,`uint8`)中按位声明本键盘支持
的 A 组字段子集(1 = 支持 / 字段有效,0 = 不支持 / 字段 MUST 不被 app 渲染)。本次分配:

| Bit | Mask | 含义 |
|-----|------|------|
| 0   | 0x01 | `is_split`(分体键盘,ZMK 绑定 `CONFIG_ZMK_SPLIT`) |
| 1   | 0x02 | `has_host_connection`(主机连接状态字段有效) |
| 2   | 0x04 | `has_profile`(BLE profile 字段有效) |
| 3   | 0x08 | `has_split_link`(分体左右半在/离线字段有效,**要求 bit 0 = 1**) |
| 4   | 0x10 | `has_output_endpoint`(输出端点字段有效) |
| 5   | 0x20 | `has_left_charging`(左半或整板充电位有效) |
| 6   | 0x40 | `has_right_charging`(右半充电位有效,**要求 bit 0 = 1 且 bit 5 = 1**,整板时固件 MUST 发 0) |
| 7   | 0x80 | reserved(1.1 必须发 0) |

### Rationale
- 一字节空间已覆盖本期全部字段 + 1 位预留给下一个 MINOR(如 B 组 WPM)。
- `is_split` 与 `has_split_link` 分开:存在"是分体但固件暂未实现 peripheral 在线上报"的情形(新 ZMK 添加 split 后再加同步事件),允许声明"我是分体,但 split_link 字段尚不可信"。
- `has_left_charging` / `has_right_charging` 分开:存在"分体但左右半 charger 硬件不对称"的情形(例如只有左半有 charger GPIO),允许一侧可见、一侧完全隐藏(符合 Principle IV 的"字段级诚实降级")。整板键盘 `has_right_charging` MUST = 0,`charging_flags.bit 1` MUST = 0。
- app **MUST** 对未知 bit(bit 7)忽略,保证下一个 MINOR 可继续追加。

### Alternatives Considered
- **用独立的 capability-service characteristic**:再多一个 CCC,收益极小。**拒绝**。
- **用 TLV 变长结构**:灵活但复杂度高、不符合 KBP"小而严"的美学。**拒绝**。

---

## 5. `Connectivity` payload 布局

### Decision
固定头 + 可选尾部的小端序结构(与 KBP 1.0 §4 风格一致):

| Offset | Size | Field | 含义 |
|--------|------|-------|------|
| `[0]`  | 1    | `capability_bits` | 见 §4 |
| `[1]`  | 1    | `host_state` | bit 0: 已连接(1 已连 / 0 未连);bits 1–2: 断连来源(0=未知 / 1=主动 / 2=超时);bits 3–7 reserved |
| `[2]`  | 1    | `profile_index` | `uint8`,1 起;0 表示"不适用/未知"。bit 7 作为 `profile_open`(open=1 待配对) |
| `[3]`  | 1    | `profile_max_slots` | `uint8`,固件声明的最大槽位数。0 表示"字段不适用" |
| `[4]`  | 1    | `split_link_flags` | bit 0: left_online;bit 1: right_online。仅当 `has_split_link = 1` 时有效 |
| `[5]`  | 1    | `output_endpoint` | 0=未知 / 1=USB / 2=BLE / 3+ 保留给未来扩展 |
| `[6]`  | 1    | `charging_flags` | bit 0: left_charging / 整机_charging(if `is_split=0`);bit 1: right_charging(仅 `is_split=1`) |
| `[7..]`| ≥0   | reserved | 未来 MINOR 的追加字节;app MUST 忽略 |

- 最小长度 = 7 字节;app 收到少于 7 字节 MUST **丢弃并记一次结构化警告**(与 §7.1 的"≥ 2 字节"同族规则)。
- 当某 bit 对应的 capability bit = 0 时,对应字段 **语义忽略**(但 payload 位置保留 0),简化 wire 布局。
- `profile_index` 的 bit 7 复用为 `profile_open`:1 字节可表达索引 0–127 外加 open flag,充分够用(ZMK 当前 5 槽位)。

### Rationale
- 固定布局比变长 TLV 对小 MCU 固件更友好;app 侧解析也更简单(直接下标访问)。
- 7 字节包含了全部 A 组状态性字段,仍远小于默认 ATT MTU(23 bytes payload)。

### Alternatives Considered
- **TLV / Protobuf 风格**:节省未上报字段的字节,但增加嵌入式实现负担。**拒绝**。
- **把 `profile_open` 单独一字节**:浪费;7-bit index + 1-bit flag 对现有 ZMK 的 5 slots 完全足够。**拒绝**。

---

## 6. `Battery` payload 布局

### Decision

| 情形 | payload |
|------|---------|
| `is_split = 0` | `[0]` 单字节,`overall_battery_percent`(`uint8`,0–100;101–254 保留;255 表示"读取失败 / 临时不可用") |
| `is_split = 1` | `[0]` `left_battery_percent`、`[1]` `right_battery_percent`(各 `uint8`,规则同上) |

- 协议层**透传原始值**(Edge Case 已约定);app 展示层 **MAY** 做小幅平滑,但 MUST 不改写协议端值。
- notify 节流:FR-008 规则(≥ 1 pp 变化或 ≥ 1s 距上次 notify)在**固件侧**实施。

### Rationale
- 单设备 1 字节 / 分体 2 字节,极小。
- `255` 作为"不可读"哨兵,比缺省字段更明确——配对电量 IC 短暂失联等 corner case 可诚实表达。

### Alternatives Considered
- **用 `uint16` 存毫伏值**:信息更多,但 UI 需要再换算,且不同板的额定电压不同不便标准化。**拒绝**。
- **始终发 2 字节**(整机场景浪费 1 字节 = 0):省不了多少,反而让"是否分体"从 payload 长度看不出来。**拒绝**。

---

## 7. notify 节流的具体阈值

### Decision
由 clarify 阶段 Q4 固化:
- **状态性字段**:状态变化**立即** notify,不设最小间隔。
- **数值性字段**(电量):满足 (a) 变化 ≥ 1 个百分点,**或** (b) 距上一次该字段 notify ≥ 1 秒,两者**或**关系触发 notify。
- 继承 KBP 1.0 §5 的"snapshot 未变不发"抑制规则,**所有** 新字段的 raw-equal snapshot 不触发 notify。

### Rationale
- 1 pp / 1 s 两条**或**线组合:电量快速变化时每 pp 都发(保证 SC-003 的 ±5% 偏差);电量稳定时每秒最多 1 条(避免打字时带宽占用)。
- 状态性字段天然低频,立即发不会压垮 BLE。

### Alternatives Considered
- **固定 1 Hz 发送**:简单但对"5% 跳变"场景会错过中间态。**拒绝**。
- **纯事件驱动,不设间隔上限**:电量 ADC 读数本身有噪声,会把 1% 抖动放大为高频 notify。**拒绝**。

---

## 8. Staleness 判定(FR-015)

### Decision
app 侧每个字段维护一个"最后一次 notify 到达时间"的单调时钟(`CFAbsoluteTimeGetCurrent()`
或 `DispatchTime.now()`),后台调度 1 Hz 检查:若 `now - lastSeen >= 3.0` 秒,将字段渲染
降级为"灰显 + 文案 '最后更新于 hh:mm:ss'"。断连事件(BLE `didDisconnectPeripheral`)
触发立即降级(不等 3 秒)。重新 notify 后立即恢复"实时"渲染。

### Rationale
- 单调时钟不受系统时间变更影响。
- 1 Hz 轮询的 cost 可忽略(< 0.1% CPU)。
- 事件 + 定时两路驱动,保证断连和"路径还活着但键盘不发"两种情况都被覆盖。

### Alternatives Considered
- **纯事件驱动**:链路活着但键盘不再发字段的场景(如固件 bug)永远不会降级,违反 FR-015 本意。**拒绝**。
- **把 3 秒做成可配置**:增加表面积而无需求驱动。**拒绝**。

---

## 9. ZMK 固件参考实现的字段映射

### Decision
在 `protocol/README.md §12 Reference implementation notes` 中补充(非规范性):

| KBP 1.1 字段 | ZMK 事件/API 参考 |
|--------------|------------------|
| `is_split` 位 | `IS_ENABLED(CONFIG_ZMK_SPLIT)` + `IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)` |
| `has_host_connection` + `host_state.connected` | `ZMK_SUBSCRIPTION(…, zmk_ble_active_profile_changed)` + `zmk_ble_active_profile_is_connected()` |
| `profile_index` + `profile_open` + `profile_max_slots` | `zmk_ble_active_profile_index()`、`zmk_ble_active_profile_is_open()`、`ZMK_BLE_PROFILE_COUNT` |
| `split_link_flags` | `zmk_split_bt_peripheral_status_changed` 事件 |
| `output_endpoint` | `zmk_endpoint_selection_changed` 事件 + `zmk_endpoints_selected()`(映射 USB_HID / BLE) |
| `charging_flags.bit 0`(`has_left_charging`) | 可选:board-local charger GPIO(整板时为 overall;多数板无,该半字段隐藏) |
| `charging_flags.bit 1`(`has_right_charging`) | 可选:peripheral 侧 charger GPIO 经分体同步总线上报(仅 split central 需要) |
| `overall_battery` / `left_battery` / `right_battery` | `zmk_battery_state_changed` + `zmk_peripheral_battery_state_changed`(central 侧) |

### Rationale
- 这些 API 名**仅为参考**,各 ZMK 版本可能有变更;具体 Hook 名由 `zmk-keybeacon` 外部模块在 implement 阶段核对。
- 字段 ↔ 事件一一对应,允许 central 的 KBP 实现用 ZMK 的事件总线纯响应式更新 payload,不需要周期性轮询。

### Alternatives Considered
- **固件侧每 1 Hz 整体轮询**:违反 ZMK 事件驱动惯例,打字时额外 cost。**拒绝**。

---

## 10. 跨平台一致性 CLI 的实现

### Decision
用 `bleak`(https://bleak.readthedocs.io)作为跨平台 BLE 后端重写 `conformance/conformance_tool.py`,支持 macOS 12+ / Linux(BlueZ 5.56+)/ Windows 10+。保留现有 PyObjC 版本为 `conformance/conformance_tool_macos.py`,作为 macOS 原生快速自测与 bleak 不可用时的 fallback。

- 新工具的入口:`python3 conformance/conformance_tool.py [--timeout SEC] [--observe SEC] [--json]`。
- Exit code 契约与现版一致(0 pass / 1 required 项失败 / 2 环境错误)。
- 新增 `--json` 输出"**支持矩阵**"(见 contracts/conformance-cli.md),被 `/speckit-implement` 阶段的脚本直接消费。

### Rationale
- `bleak` 是目前 Python 生态**事实上的** 跨平台 BLE 库,维护活跃、API 简洁、支持已连接外设枚举(macOS 的 `retrieveConnectedPeripherals` 等价)。
- 与 Spec FR-012 的"MUST 作为跨平台 CLI 交付"直接对齐。
- 旧 PyObjC 工具不删,**按用户规则所有删除前先备份**,通过 `git mv` 保留历史。

### Alternatives Considered
- **纯 Python + hciutil / shell 调用**:只能 Linux,不符合跨平台要求。**拒绝**。
- **Rust / Go 跨平台 BLE 库 + 发 release 二进制**:工具链太重,违反"自测工具应该键盘作者零门槛接入"的初衷。**拒绝**。
- **直接废弃 PyObjC 工具**:违反用户的"删除前备份"规则。**保留**。

---

## 11. 向后兼容的具体行为

### Decision

| 场景 | 行为 |
|------|------|
| **新 app** 连 **老固件(KBP 1.0)** | GATT 服务发现只看到 `AA440AA1-…`;app `BLEClient` 不订阅 1.1 特征;`FloatingPanel` 的「连接与电量」卡片**整张隐藏**(不占位);菜单栏行为与 KBP 1.0 完全一致 |
| **老 app(KBP 1.0)** 连 **新固件(KBP 1.1)** | 老 app 只订阅 `AA440AA1-…`,对 `AA2` / `AA3` 的存在无感知;固件对未订阅特征不浪费 notify 带宽;老 app 行为完全不变 |
| **新 app + 新固件,固件字段部分缺失**(例如仅实现主机连接,未实现电量) | `Connectivity` 特征的 capability bits 中对应 bit = 0;Battery 特征可能干脆不实现(此时 GATT 发现看不到 `AA3`,整个电量 UI 隐藏);UI 做字段级显隐 |
| **新固件声明 is_split 但只上报一侧电量** | Battery payload 长度 = 2,未知侧填 `255`(FR-007 的 sentinel);UI 对该半电量显示"读取失败"而非具体数字 |

### Rationale
全部兜底路径都复用现有机制:service UUID 分辨 MAJOR;characteristic 存在性分辨 MINOR;capability bits 分辨字段级能力。三级能力探测与 `KBPCompatibility.swift` 现有分类器正交。

---

## 12. 诊断日志(FR-018)

### Decision
用 `os.Logger`(macOS)输出结构化行,subsystem = `com.keybeacon.app`,category 新增
`capability` / `staleness` / `connection`。字段按 OSLog 的 `%{public}@` + `%{public}d`
显式格式化,保证从 Console.app 和 `log stream` 都可过滤。

关键事件:
- `capability.discovered`:发现并解析了新设备的能力位 → 记录能力位二进制值与 bit-level 解析
- `connection.state_changed`:主机连接 bit 翻转时的时间戳与来源字节
- `staleness.field_stale` / `staleness.field_live`:字段跨越 3 秒阈值时各发一次

### Rationale
- 复用现有 OSLog 栈,无新依赖。
- 对最终用户不可见、对键盘作者和开发者可过滤。

### Alternatives Considered
- **写文件日志**:macOS 用户期待看 Console.app;文件日志反而难清理。**拒绝**。

---

## 13. 测试策略

### Decision
- **协议层**:无自动化测试;通过一致性 CLI 的字段级 PASS/FAIL 条目间接验证。
- **一致性 CLI**:主体为**行为级手工自测**;可以为 payload 解析函数写 pytest 单测(例如字节序列 → 字段 dict)。
- **macOS 应用**:XCTest 单测 **4 个新模型 + 修改的 BLEClient 的 payload 分发逻辑**。UI 层(FloatingPanel)不写 UI 测试,通过 quickstart.md 的手工脚本验证。
- **端到端**:quickstart.md 的脚本以参考分体键盘运行,配合一致性 CLI 的 `--json` 支持矩阵输出做"自动化冒烟"。

### Rationale
与现有仓库测试风格(XCTest 单测 + conformance CLI + 手工自测脚本)完全一致,不引入新测试栈。

---

## 14. 兼容性与设计原则(自我约束 re-check)

| 自我约束 | 本设计符合情况 |
|---------|--------------|
| 向后兼容优先 | ✅ service UUID 不变,老 app/固件完全不变 |
| wire 契约 self-contained | ✅ 新特征所有字段在协议文档中规范,无需固件代码即可实现另一端 |
| 身份只来自服务 UUID,显示只来自 GAP 名 | ✅ 本 feature 不新增任何型号识别 |
| snapshot 未变不发 | ✅ FR-008 显式继承 §5 的抑制规则 |
