# KeyBeacon Roadmap

**English** · [中文](#zh-roadmap) · [← Back to README](../README.md)

<a id="en-roadmap"></a>

Where KeyBeacon is headed — a catalogue of candidate metrics worth surfacing for a screenless
(especially wireless split) keyboard. Each item is a self-contained **KBP MINOR** addition (a new
optional BLE characteristic across **protocol → firmware → app**), so apps on an older protocol
ignore what they don't recognize and keep working. Feasibility assumes ZMK, which is event-driven:
items marked *High* already have firmware events to hook; exact API names are confirmed per item at
spec time. These are candidates, not commitments.

## A. Connectivity & power

> **Status**: ✅ **Shipped in KBP 1.1** — released 2026-10-09. **Per-link host context shipped in KBP 1.2** — released 2026-11-08.
> Specification: [`specs/001-connectivity-power/spec.md`](../specs/001-connectivity-power/spec.md)
> and [`specs/005-host-link-profile-awareness/spec.md`](../specs/005-host-link-profile-awareness/spec.md);
> firmware module: [`zmk-keybeacon@v1.1.2`](https://github.com/ykiewang/zmk-keybeacon/releases/tag/v1.1.2)
> (KBP 1.1) / [`zmk-keybeacon@v1.2.0`](https://github.com/ykiewang/zmk-keybeacon/releases/tag/v1.2.0) (KBP 1.2)
> ([CHANGELOG](https://github.com/ykiewang/zmk-keybeacon/blob/main/CHANGELOG.md));
> normative wire contract: [`protocol/README.md §14`](../protocol/README.md#14-kbp-11-connectivity--power-optional)
> and [`§15`](../protocol/README.md#15-kbp-12-per-link-host-context-optional).

| Metric | Status | Why it helps a screenless split | ZMK feasibility | Protocol impact |
|--------|--------|---------------------------------|-----------------|-----------------|
| Host link status | ✅ Shipped (v1.1) | is the keyboard actually connected to the host | High — active-profile connected state + event | KBP 1.1 · AA2 bytes `host_state` + `last_disconnect_reason` |
| Active BLE profile | ✅ Shipped (v1.1) | which profile slot (1–5), and whether it's open for pairing | High — profile index / open state | KBP 1.1 · AA2 bytes `profile_index` + `profile_max_slots` |
| Per-half link status | ✅ Shipped (v1.1) | a split half dropping offline is visible at a glance | High — proxied via `zmk_peripheral_battery_state_changed` + 75 s TTL (ZMK does not expose a central-side split-link API at commit `6b44d33d`) | KBP 1.1 · AA2 `split_flags` bits 0–1 |
| Per-half battery | ✅ Shipped (v1.1) | know which half to charge | High — battery + peripheral-battery events (requires `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y`) | KBP 1.1 · AA3 payload `[0]` / `[1]` |
| Active output | ✅ Shipped (v1.1) | whether keystrokes go to USB or BLE | High — `zmk_endpoints_selected()` + change event | KBP 1.1 · AA2 `output_endpoint` byte |
| Per-link host context | ✅ Shipped (v1.2) | tells *this* computer whether the keyboard is typing here vs active on another host — zero config | High — per-connection READ resolves the asking host's bonded slot ([`specs/005-host-link-profile-awareness/spec.md`](../specs/005-host-link-profile-awareness/spec.md)) | KBP 1.2 · AA4 `local_link_profile` (READ-only, per-connection) |
| Charging status | ⚠️ Protocol-defined; hardware-dependent (corne lacks a charge-detect GPIO, so capability bits 5–6 stay `0`) | whether a half is charging | Low — most boards lack a charge-detect pin | KBP 1.1 · AA2 `charging_flags` bits 0–1 (opt-in via capability bits) |

## B. Input & lock state

> **Status**: 📋 Planned — no implementation yet. Would land as additive **KBP 1.2** fields.

| Metric | Why it helps a screenless split | ZMK feasibility | Protocol impact |
|--------|---------------------------------|-----------------|-----------------|
| Caps-Word active | visualize Caps-Word with no indicator LED | Medium — behavior state needs a small hook | KBP 1.2 · field |
| Host lock LEDs | Caps / Num / Scroll Lock reported by the host | High — HID indicators + change event | KBP 1.2 · field / characteristic |
| Full active-layer stack | see every active layer, not just the top one | High — iterate per-layer active state | KBP 1.2 · appended field |
| Sticky / one-shot pending | a pending sticky modifier or layer | Medium — partly already in `mods` | KBP 1.2 · field (partial overlap) |

## C. Typing stats

> **Status**: 📋 Planned — no implementation yet. Would land as additive **KBP 1.2+** characteristics.

| Metric | Why it helps | ZMK feasibility | Protocol impact |
|--------|--------------|-----------------|-----------------|
| Typing speed (WPM) | live words-per-minute | Medium — no native WPM; module counts keypresses | KBP 1.2 · new characteristic (throttle while typing) |
| Keystroke / session count | usage over a session | Medium — count keypress events | KBP 1.2 · stats characteristic |
| WPM peak / rolling average | trend over time | Medium — derived from WPM | KBP 1.2 · stats characteristic |

## D. Device health

> **Status**: 📋 Planned — no implementation yet. Order TBD; `RSSI` is lowest priority.

| Metric | Why it helps | ZMK feasibility | Protocol impact |
|--------|--------------|-----------------|-----------------|
| Activity state | tell when a half has gone idle / asleep | High — activity state + event | KBP 1.x · field |
| RGB / backlight state | confirm effect, brightness, on/off after a blind toggle | Medium — underglow / backlight getters + events | KBP 1.x · characteristic |
| Link quality (RSSI) | signal strength of the host or split link | Low — needs HCI; not exposed by default | later |
| Uptime | time since last reset (diagnostics) | High but low value — `k_uptime` | KBP 1.x · field |

---

<a id="zh-roadmap"></a>

# KeyBeacon 路线图

[English](#en-roadmap) · **中文** · [← 返回 README](../README.zh-CN.md)

KeyBeacon 的下一步走向——一份面向无屏(尤其是无线分体)键盘、值得展示的候选指标目录。每一项都是一个
自包含的 **KBP MINOR** 增量(新增一个可选的 BLE 特征,贯穿 **协议 → 固件 → app**),旧版应用会忽略
不认识的部分并继续正常工作。可行性以 ZMK 为准,ZMK 是事件驱动:标 *高* 的项已有现成固件事件可挂接;
具体 API 名在各项 spec 阶段再核对。以下均为候选项,而非承诺。

## A. 连接与电量

> **状态**：✅ **KBP 1.1 已发布**（2026-10-09）；**KBP 1.2 每连接主机上下文已发布**（2026-11-08）。规范：
> [`specs/001-connectivity-power/spec.md`](../specs/001-connectivity-power/spec.md) 与
> [`specs/005-host-link-profile-awareness/spec.md`](../specs/005-host-link-profile-awareness/spec.md)；规范化
> 线上契约：
> [`protocol/README.md §14`](../protocol/README.md#14-kbp-11-连接与电量可选特征) 与
> [`§15`](../protocol/README.md#15-kbp-12-每连接主机上下文可选特征)。

| 指标 | 对无屏分体的价值 | ZMK 可行性 | 协议影响 |
|------|----------------|-----------|---------|
| 主机连接状态 | 键盘是否真的连上了主机 | 高——当前 profile 连接状态 + 事件 | KBP 1.1 · 新增特征 |
| 当前 BLE profile | 在第几个槽位(1–5)、是否待配对 | 高——profile 索引 / open 状态 | KBP 1.1 · 同一特征 |
| 左右半连接状态 | 分体某半掉线一眼可见 | 高——central 侧 peripheral 状态事件 | KBP 1.1 · 新增特征 |
| 每半电量 | 知道该充哪一半 | 高——battery + peripheral battery 事件 | KBP 1.1 · 新增特征 |
| 当前输出 | 键击去向 USB 还是 BLE | 高——选定端点 + 变更事件 | KBP 1.1 · 字段 / 特征 |
| 每连接主机上下文 | 告诉*这台*电脑：键盘正在此打字，还是在另一台机上活跃——零配置 | 高——每连接 READ 解析发起主机的绑定槽位（[`specs/005-host-link-profile-awareness/spec.md`](../specs/005-host-link-profile-awareness/spec.md)） | ✅ 已发布 (v1.2) · KBP 1.2 · AA4 `local_link_profile`（只读、每连接） |
| 充电状态 | 某半是否在充电 | 低——多数板无充电检测引脚 | 可选 · 依赖硬件 |

## B. 输入与锁定状态

> **状态**：📋 规划中——尚无实现。将作为增量 **KBP 1.2** 字段落地。

| 指标 | 对无屏分体的价值 | ZMK 可行性 | 协议影响 |
|------|----------------|-----------|---------|
| Caps-Word 激活 | 无指示灯时可视化 Caps-Word | 中——行为状态需小 hook | KBP 1.2 · 字段 |
| 主机锁定灯 | 主机上报的 Caps / Num / Scroll Lock | 高——HID 指示器 + 变更事件 | KBP 1.2 · 字段 / 特征 |
| 完整激活层栈 | 看清每个激活层,不止最高层 | 高——遍历各层激活状态 | KBP 1.2 · 追加字段 |
| Sticky / one-shot 待定 | 挂起的粘滞修饰键或层 | 中——部分已含在 `mods` | KBP 1.2 · 字段(部分重叠) |

## C. 打字统计

> **状态**：📋 规划中——尚无实现。将作为增量 **KBP 1.2+** 特征落地。

| 指标 | 价值 | ZMK 可行性 | 协议影响 |
|------|------|-----------|---------|
| 打字速度(WPM) | 实时每分钟字数 | 中——无原生 WPM;模块内计数 keypress | KBP 1.2 · 新增特征(打字时需节流) |
| 击键 / 会话计数 | 一次会话的使用量 | 中——计数 keypress 事件 | KBP 1.2 · stats 特征 |
| WPM 峰值 / 滚动均值 | 趋势 | 中——由 WPM 派生 | KBP 1.2 · stats 特征 |

## D. 设备健康

> **状态**：📋 规划中——尚无实现。顺序待定；`RSSI` 优先级最低。

| 指标 | 价值 | ZMK 可行性 | 协议影响 |
|------|------|-----------|---------|
| 活动状态 | 看出某半是否空闲 / 休眠 | 高——活动状态 + 事件 | KBP 1.1 · 字段 |
| RGB / 背光状态 | 盲切后确认效果、亮度、开关 | 中——underglow / backlight getter + 事件 | KBP 1.x · 特征 |
| 连接质量(RSSI) | 主机或分体链路信号强弱 | 低——需 HCI,默认不暴露 | 后期 |
| 运行时长 | 距上次复位的时间(诊断) | 高但价值低——`k_uptime` | KBP 1.x · 字段 |
