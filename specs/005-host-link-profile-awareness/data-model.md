# Phase 1 Data Model: 每连接主机上下文（Per-Link Host Context）

**Feature**: `specs/005-host-link-profile-awareness` | **Date**: 2026-11-02 | **Plan**: [plan.md](./plan.md)

本文件定义本 feature 涉及的**数据实体、字段、wire 偏移与派生规则**。wire 契约的唯一真相源仍是 `protocol/README.md`（本 feature 会发布新增可选特征的 MINOR 增量）；本文件是其**面向实现的投影**，供 macOS `BleWidgetCore` 与 Windows `KeyBeacon.Core` 两端同构实现。数据在两端以**纯逻辑类型**承载（无平台依赖），可脱离 BLE 硬件单测。

> **方案 A（已选定）**：新增独立**只读**特征 `AA440AA4-…` 承载 per-link slot。**既有 `AA440AA0/AA1/AA2/AA3` 全部不变**（含 AA2 的 `[0..6]` 与 byte0 bit7）。本 feature 对既有 wire **零改动**，纯加法。

---

## 0. UUID 常量

| 名称 | UUID | 属性 | 说明 |
|------|------|------|------|
| service | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` | — | KBP 服务；MAJOR 版本信号（不变） |
| status (AA1) | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` | READ\|NOTIFY | KBP 1.0 层+修饰键（不变） |
| connectivity (AA2) | `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` | READ\|NOTIFY | KBP 1.1 连接（**不变**） |
| battery (AA3) | `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` | READ\|NOTIFY | KBP 1.1 电量（不变） |
| **link-slot (AA4)** | **`AA440AA4-F5ED-4C48-84A1-8062D20D3D55`** | **READ only（无 NOTIFY / 无 CCC）** | **[NEW] 本连接 slot（per-connection）** |

两端 UUID 常量：macOS `BLEClient.swift:53-64`；Windows `KbpUuids.cs`。本 feature 各加一个 AA4 常量。

---

## 1. LinkSlot 特征 payload（AA4，新增）

### 1.1 布局（little-endian，固定长度 ≥ 1 字节）

| Offset | Size | Field | 范围 / 编码 |
|--------|------|-------|-------------|
| `[0]` | 1 | `local_link_profile` | bits 0–6：**本连接 slot**，1-based（`0` = 未确定/不适用）；bit 7：reserved（1.2 固件 MUST 0） |
| `[1..N]` | ≥0 | reserved trailing | 未来 MINOR 字段；consumer MUST ignore |

### 1.2 per-connection 语义（关键）

- AA4 **只有 READ 属性**（无 NOTIFY）。因此 READ 响应 = **发起该读的这条 BLE 连接**对应的 slot。
- 不存在「广播帧污染」问题：只读特征物理上不会推送通知，host 读到的值**必然**是本连接值。这是方案 A 相对「AA2 尾部加字段」方案的**核心区别**。

### 1.3 生产者不变量（固件 MUST）

- **P-L1**：AA4 若暴露 → 属性恰为 `READ`（无 `NOTIFY`、无 CCC `0x2902`）。
- **P-L2**：`[0].bits0–6 == 0` 表示「本连接无法解析到任何 slot」（含空/未配对/open/私有地址不匹配）—— MUST NOT 发猜测值（FR-003）。
- **P-L3**：`[0].bits0–6 > 0` 时 MUST ≤ `profile_max_slots`（与 AA2 的 P-C3 一致，不越界）。
- **P-L4**：`[0].bit7` MUST 为 0（reserved）。
- **P-L5**：AA4 与 AA2 一样，仅由 split 键盘的**中心（host-link）角色**暴露（§14 C12 精神延伸）。

### 1.4 消费者规则（主机 MUST）

- **C-L1**：发现 AA4 存在 → 支持 per-link；READ 一次取 `local_link_profile`。
- **C-L2**：未发现 AA4（老固件）→ **MUST NOT** 渲染 in-use/elsewhere，仅显示 link 级状态（`disconnected`/`cannot-determine`），不臆造 slot。
- **C-L3**：AA4 payload 长度 < 1 字节 → drop 并发 `hostlink.cannot_determine`，视为未确定。
- **C-L4**：`local_link_profile.bits0–6 > profile_max_slots` → clamp 到 `profile_max_slots` 显示并发 `profile.out_of_range`（沿用 AA2 的 C-C4 精神；`profile_max_slots` 取自 AA2 `[3]`）。
- **C-L5**：payload `[1..]` 尾部 MUST ignore（MINOR forward-compat）。
- **C-L6**：AA2 的 `[0..6]` 解析、能力位 gating、`C-C1..C-C7` **全部保持不变**。

---

## 2. CapabilityMatrix（不变）

**方案 A 不改 CapabilityMatrix**。byte0 bit7 仍为 `reserved7`（1.1 语义不变）。per-link 支持与否**不经能力位**判定，而经 **AA4 特征是否存在** 判定（与 AA2/AA3 探测一致）。

| bit | 字段 | 说明 |
|-----|------|------|
| 0 | IsSplit | 不变 |
| 1 | HasHostConnection | 不变 |
| 2 | HasProfile | 不变 |
| 3 | HasSplitLink | 不变 |
| 4 | HasOutputEndpoint | 不变 |
| 5 | HasLeftCharging | 不变 |
| 6 | HasRightCharging | 不变 |
| 7 | reserved7 | **不变**（仍 reserved，MUST 0） |

---

## 3. LinkSlot（新实体，解析 AA4）

**含义**：本 BLE 连接对应的 profile slot（per host, per connection）。

| 属性 | 类型 | 来源 | 说明 |
|------|------|------|------|
| `slot` | int | AA4 `[0].bits0–6` | 1-based；`0` = not-determined / not-applicable |
| `known` | bool | 派生 | `slot >= 1 && slot <= maxSlots`（maxSlots 来自 AA2 `[3]`） |
| `learnedAt` | timestamp | 宿主记录 | 学到 slot 的时刻（诊断/会话记忆用） |

- **Parse**：`data.Length < 1` → `null`（C-L3）。`slot = data[0] & 0x7F`。`data[0] & 0x80`（bit7）忽略。尾部忽略。
- **纯函数**：`LinkSlot.parse(bytes) -> LinkSlot?`，无 I/O，可穷举单测。
- **生命周期**：会话级内存缓存；连接/重连、`profile_open` 1→0、active 变化、周期兜底 → 重读刷新（research D3）。重新配对到别的 slot 靠下次连接/重读再学（US2）。

---

## 4. ActiveProfile（AA2 既有字段的显式化，不改 wire）

**含义**：键盘**全局活跃** profile（AA2 广播，跨主机相同）。

| 属性 | 类型 | 来源 |
|------|------|------|
| `index` | int | AA2 `[2].bits0–6`（1-based；0=n/a） |
| `isOpen` | bool | AA2 `[2].bit7`（1=waiting-to-pair） |
| `maxSlots` | int | AA2 `[3]` |

`isOpen == 1` → 无活跃目标 → 派生状态降级 `cannot-determine`（不臆造 slot）。

---

## 5. OutputEndpoint（AA2 既有字段的复用）

| 值 | 语义 | 对状态派生的作用 |
|----|------|------------------|
| 0 | unknown | 不据此判 on-usb |
| 1 | USB | connected 且 `has_output_endpoint` → `on-usb`（优先于 in-use over BLE） |
| 2 | BLE | 正常参与 in-use/elsewhere 判定 |
| 3–255 | reserved | 视 unknown（显示 `unknown endpoint (0x__)`，C-C5） |

---

## 6. LocalHostStatus（派生枚举，五态）

**定义**（唯一、端到端一致的 5 态；两端同名枚举）：

| 枚举 | 中文 UI | 英文 UI |
|------|---------|---------|
| `inUseHere` | 正在此电脑使用 | In use on this computer |
| `activeElsewhere(slot:N)` | 键盘正在另一台电脑使用（P{N}） | Keyboard active on another computer (P{N}) |
| `onUsb` | 键盘在 USB 输出（非本 BLE 链路） | Keyboard on USB (not this BLE link) |
| `cannotDetermine` | 无法确定 | Cannot determine |
| `disconnected` | 未连接 | Disconnected |

### 6.1 派生纯函数（伪代码，两端同构）

```text
deriveLocalHostStatus(hasAA4, cap, link, active, local, output):
    if !link.connected:                         return .disconnected          # 最高优先级
    if cap.hasOutputEndpoint && output == USB:  return .onUsb
    if !hasAA4:                                 return .cannotDetermine        # 老固件，未发现 AA4
    if !cap.hasProfile || active.index == 0 || active.isOpen:
                                                return .cannotDetermine        # open/n/a
    if local.slot == 0:                         return .cannotDetermine        # 固件未解析
    if active.index == local.slot:              return .inUseHere
    else:                                       return .activeElsewhere(active.index)
```

- **纯函数**：入参为「已解析字段 + AA4 是否存在」，无 I/O、无全局态 → 可直接穷举单测（FR-014）。
- **优先级**：`disconnected` 最高（FR-009）；`onUsb` 先于 in-use（edge case）；无正向确认 → `cannotDetermine`（FR-008）。

### 6.2 FR / 边界映射

| spec 条目 | 派生体现 |
|-----------|----------|
| FR-001 零配置拿 slot | 发现 AA4 → 读 → 得 slot，无用户输入 |
| FR-004 独立于广播 | AA4 独立特征，不依赖 AA2 NOTIFY |
| FR-005 五态 | 枚举五值 |
| FR-006 ≤1 s 更新 | AA2 notify / AA4 重读 / 连接态任一变化即重派生 |
| FR-008 无正向确认不渲染 in-use | 未发现 AA4 / 任一输入缺 → `cannotDetermine` |
| FR-009 断连优先 | `disconnected` 短路 |
| FR-010 中英双语 | §6 两语 UI 文案 |
| edge: USB 输出 | `onUsb` |
| edge: open slot | `active.isOpen` → `cannotDetermine` |
| edge: 单主机 | `active.index == local.slot` → `inUseHere` |
| edge: 快速切换 | 重派生 + 只信最终 active（无陈旧 in-use） |

---

## 7. 状态持久化与陈旧

- **无持久化实体**：`LinkSlot` 为会话级内存缓存；不落盘、不跨启动记忆（避免「上次 slot」误导）。重新连接即重新学习。
- **陈旧**：`LocalHostStatus` 不单独做陈旧窗口；随输入字段刷新。链路断开 → `disconnected` 立即覆盖（各端 `StalenessTracker.forceStaleAll()` 已有机制）。
- **诊断**：`hostlink.unresolved` / `hostlink.cannot_determine` / `hostlink.read_back_slot`（见 research §4）。

---

## 8. 与既有实体的关系

| 既有实体 | 关系 |
|----------|------|
| `KeyboardStatus`（AA1） | **不变** |
| `CapabilityMatrix` | **不变**（bit7 仍 reserved） |
| `ConnectivityStatus`（AA2） | **不变**（仅被派生函数**读取** index/open/output/connected） |
| `BatteryStatus`（AA3） | **不变** |
| `StalenessTracker` | 复用，无改动 |
| `BLEConnectionState`(macOS)/`MonitorState`(Windows) | **不复用**（transport 级）；新增 `LocalHostStatus`/`HostContextStatus` |
| **`LinkSlot`（AA4）** | **新增**纯类型 |
