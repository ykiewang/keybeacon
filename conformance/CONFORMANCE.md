<a id="en-conformance"></a>

# Making a keyboard conform to KeyBeacon (KBP)

**English** · [中文](#zh-conformance)

This guide is the **complete, concrete body of work** to make a keyboard work with KeyBeacon and
to prove it. It is normative for the claim "this keyboard supports KBP". The authoritative wire
contract is [`../protocol/README.md`](../protocol/README.md); this document tells a keyboard author
**what to build**, and [`checklist.md`](checklist.md) + [`conformance_tool.py`](conformance_tool.py)
tell them **how to verify** it.

You can implement KBP on any firmware stack and any BLE library — KBP is defined only by what
appears on the air. The notes below call out the ZMK reference path where helpful, but nothing here
requires ZMK.

## 0. Prerequisite: the keyboard must own the host BLE link (central role)

KeyBeacon reports state to a desktop host over the keyboard's **host-facing BLE connection**. The
keyboard must therefore be the device the host connects to:

- **Unibody / single-MCU keyboard**: it already is the host-link device — nothing special.
- **Split keyboard**: only the half that holds the **central (host-link) role** exposes KeyBeacon.
  The peripheral half and any `settings_reset`/recovery image **must not** include it. (In the ZMK
  reference, that means the KeyBeacon kit is gated to the central build only.)

If your keyboard cannot act as the host-link BLE device, it cannot implement KBP as specified.

## 1. Expose the service and characteristic

Add one custom GATT **primary service** with one **status characteristic**:

| Item | Value |
|------|-------|
| Service UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` |
| Status characteristic UUID | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` |
| Properties | `READ` **and** `NOTIFY` |
| Descriptor | Client Characteristic Configuration (CCC, `0x2902`) — required for NOTIFY |

The **service UUID is the identity and the compatibility signal**. Do not gate behavior on device
name or model. (Verified by tool check **C1**.)

## 2. Produce the status payload (≥ 2 bytes, little-endian)

The characteristic value is the variable-length snapshot from protocol §4:

| Offset | Size | Field | Source |
|--------|------|-------|--------|
| `[0]` | 1 | `layer_index` (`uint8`) | highest active layer index |
| `[1]` | 1 | `mods` (`uint8`) | held HID modifier bitmask (see §4.1) |
| `[2..N]` | ≥ 0 | `layer_name` (UTF-8, no trailing NUL) | active layer's name; MAY be empty |

Rules:

- The payload MUST be **at least 2 bytes**. `layer_name` MAY be empty (a 2-byte payload is valid).
- `layer_name` MUST be **valid UTF-8** and carry **no trailing NUL**.
- Derive everything from the keyboard's authoritative keymap/HID state — never a second cached copy.
- Keep the whole snapshot within your negotiated ATT MTU (the reference firmware truncates
  `layer_name` to 32 bytes; that is an implementation limit, not a protocol limit).

(Verified by tool check **C2**.)

## 3. Notify on change, and suppress when unchanged

- Send a **NOTIFY** whenever the snapshot changes (a layer switch or a modifier press/release).
- **Suppress** the notification when the recomputed snapshot equals the last one you sent. An idle
  keyboard MUST produce **zero** notification traffic.
- Support **READ** for the current snapshot (the host reads it once on connect, then subscribes).

(Verified by tool check **C3**: subscription succeeds and no traffic arrives while idle.)

## 4. Stay discoverable while connected

A connected BLE HID keyboard stops advertising, so the host finds it by **enumerating already-
connected peripherals** and confirming the service over GATT. You get this for free by exposing the
service on the live host connection — just make sure the service is present on the **connected**
image. (Verified by tool check **C4** when the keyboard is connected to the test host.)

## 5. Advertise a GAP device name (recommended)

Advertise a non-empty **GAP device name**; the host uses it as the display name. If absent, the host
falls back to a generic label and still connects, so this is **RECOMMENDED, not required**.
(Reported by tool check **C5**; the tool prints the discovered name so you can confirm identity.)

## 6. Verify with the conformance tool

Run the self-test against your keyboard (connect it to the test Mac first for the reliable path):

```bash
python3 conformance/conformance_tool.py            # defaults: --timeout 15 --observe 4
```

The tool discovers your keyboard **by service UUID only**, prints the discovered GAP name, and
reports **per-item PASS/FAIL/WARN** for C1–C6 (see [`checklist.md`](checklist.md)).

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | all required items pass — the keyboard conforms to KBP 1.x |
| `1` | a required conformance item failed (the output names which one) |
| `2` | environment error — Bluetooth off, no keyboard found, connect timeout, or missing deps |

Required items are **C1–C4**; **C5** is RECOMMENDED (WARN only) and **C6** (split central-only) is a
MANUAL firmware-config check the host cannot observe. A clean reference keyboard yields exit `0`.

## 7. Requirements for the tool

The primary cross-platform tool `conformance_tool.py` uses `bleak` (macOS 12+ / BlueZ 5.56+ /
Windows 10+). The legacy macOS-only PyObjC tool is retained as `conformance_tool_macos.py` for
KBP 1.0 regression and as a fallback when `bleak` is unavailable.

```bash
# Primary (recommended): cross-platform via bleak
python3 -m pip install -U -r conformance/requirements.txt
python3 conformance/conformance_tool.py              # covers C1-C12

# Legacy macOS fallback: PyObjC/CoreBluetooth, KBP 1.0 only
pip install pyobjc-framework-CoreBluetooth
python3 conformance/conformance_tool_macos.py         # covers C1-C6
```

Grant the terminal/app Bluetooth permission when macOS prompts.

## 8. A-group fields (KBP 1.1)

KBP 1.1 adds **two optional characteristics** on the same `AA440AA0-…` service. Your firmware MAY
implement either, both, or neither; a host that doesn't recognize them simply doesn't render them,
and a 1.0 host sees the 1.0 characteristic as before. This section is the implementation
counterpart to protocol §14; the wire contract remains authoritative.

### 8.1 Fields → characteristic mapping

| Field | KBP 1.1 characteristic | Byte position | Capability bit |
|-------|------------------------|---------------|-----------------|
| `is_split` | Connectivity | byte 0 bit 0 | — (declared here) |
| `host_state.connected` + `last_disconnect_reason` | Connectivity | byte 1 | `has_host_connection` (bit 1) |
| `profile_index` + `profile_open` + `profile_max_slots` | Connectivity | bytes 2–3 | `has_profile` (bit 2) |
| `split_link_flags` (left_online + right_online) | Connectivity | byte 4 | `has_split_link` (bit 3, requires `is_split`) |
| `output_endpoint` | Connectivity | byte 5 | `has_output_endpoint` (bit 4) |
| `charging_flags.bit 0` (left-half or overall charging) | Connectivity | byte 6 bit 0 | `has_left_charging` (bit 5) |
| `charging_flags.bit 1` (right-half charging, split only) | Connectivity | byte 6 bit 1 | `has_right_charging` (bit 6, requires `is_split` + `has_left_charging`) |
| `overall_battery_percent` (integer board) | Battery | byte 0 (1-byte payload) | (characteristic presence declares support) |
| `left_battery_percent` + `right_battery_percent` (split) | Battery | bytes 0 + 1 (2-byte payload) | (characteristic presence; `is_split` declares split layout) |

The `capability_bits` field (Connectivity byte 0) is the per-field support declaration. A bit set
to `0` means the host MUST hide the UI for that field entirely (per the "Observable Degradation
Over Guessing" governance principle); it MUST NOT render "N/A", "0", or any placeholder.

### 8.2 capability_bits layout (Connectivity byte 0)

| Bit | Mask | Name | Meaning |
|-----|------|------|---------|
| 0 | `0x01` | `is_split` | the keyboard is a split (ZMK: `CONFIG_ZMK_SPLIT`) |
| 1 | `0x02` | `has_host_connection` | `host_state` byte is meaningful |
| 2 | `0x04` | `has_profile` | profile fields are meaningful |
| 3 | `0x08` | `has_split_link` | split-link flags are meaningful (requires bit 0) |
| 4 | `0x10` | `has_output_endpoint` | `output_endpoint` is meaningful |
| 5 | `0x20` | `has_left_charging` | left/overall `charging_flags.bit 0` is meaningful |
| 6 | `0x40` | `has_right_charging` | right `charging_flags.bit 1` is meaningful (requires `is_split` + `has_left_charging`; integer boards MUST emit 0) |
| 7 | `0x80` | reserved | 1.1 firmware MUST emit 0 |

### 8.3 Firmware implementer roadmap (ZMK reference, non-normative)

If you're building on ZMK, these are the natural event / API hooks for each field. The
`zmk-keybeacon` external module provides a drop-in implementation; API names may evolve across ZMK
releases, so verify against ZMK main at build time.

| KBP 1.1 field | ZMK event / API hook |
|---------------|----------------------|
| `is_split` bit | `IS_ENABLED(CONFIG_ZMK_SPLIT) && IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)` (compile-time) |
| `host_state.connected` | subscribe `zmk_ble_active_profile_changed`; read `zmk_ble_active_profile_is_connected()` |
| `profile_index` + `profile_open` + `profile_max_slots` | `zmk_ble_active_profile_index()`, `zmk_ble_active_profile_is_open()`, `ZMK_BLE_PROFILE_COUNT` |
| `split_link_flags` | subscribe `zmk_split_bt_peripheral_status_changed`; read `zmk_split_bt_peripherals_connected()` |
| `output_endpoint` | subscribe `zmk_endpoint_changed`; read `zmk_endpoints_selected()` (map USB_HID → 1, BLE → 2) |
| `charging_flags.bit 0` (left/overall) | optional board-local charger GPIO (most boards do not implement) |
| `charging_flags.bit 1` (right, split) | optional peripheral-side charger GPIO reported via the split sync bus (split central only) |
| `overall_battery` / `left_battery` / `right_battery` | subscribe `zmk_battery_state_changed` + `zmk_peripheral_battery_state_changed`; aggregate on the central side |

**Throttling rules** (firmware MUST emit):

- **State-ish fields** (host_state, profile, split_link, output_endpoint, charging_flags): emit on
  change, with **no minimum interval**; inherit the KBP 1.0 "snapshot-unchanged suppression" rule
  (byte-for-byte identical snapshot ⇒ suppress NOTIFY).
- **Numeric fields** (battery percent): emit when the byte value changes by **≥ 1** OR when
  **≥ 1 second** has elapsed since the last emit on that field (OR relation), subject to the same
  snapshot-unchanged suppression.

### 8.4 Legacy macOS tool vs. cross-platform tool

| | `conformance_tool.py` (primary) | `conformance_tool_macos.py` (legacy) |
|---|---------------------------------|---------------------------------------|
| Platforms | macOS 12+, Linux (BlueZ 5.56+), Windows 10+ | macOS 12+ only |
| BLE backend | `bleak>=0.21` | PyObjC + CoreBluetooth |
| KBP coverage | KBP 1.0 (C1–C6) + KBP 1.1 (C7–C12) | KBP 1.0 only (C1–C6) |
| JSON support matrix | yes (`--json`) | no |
| Role | primary entry point and CI target | regression comparison; `bleak`-less fallback |

The legacy tool is retained unmodified except for a header comment pointing to the cross-platform
tool. Do **not** add new features (including KBP 1.1 checks) there; add them to
`conformance_tool.py` instead.

### 8.5 How to verify

```bash
python3 -m pip install -U -r conformance/requirements.txt
python3 conformance/conformance_tool.py --json | tee /tmp/kbp11_matrix.json

# Example JSON assertions:
jq '.declared_minor' /tmp/kbp11_matrix.json              # "1.0" or "1.1"
jq '.capability_bits.is_split' /tmp/kbp11_matrix.json    # bool, when 1.1
jq '.field_support.left_charging' /tmp/kbp11_matrix.json # "supported" | "unsupported" | ...
jq '.exit_code' /tmp/kbp11_matrix.json                   # 0 = conforms
```

The schema is pinned under `spec_version = "kbp-conformance-cli/1"` in the JSON output.

---

<a id="zh-conformance"></a>

# 让键盘符合 KeyBeacon（KBP）— 中文版

[English](#en-conformance) · **中文**

本指南是使键盘兼容 KeyBeacon 并加以验证的**完整、具体的工作清单**。它对"此键盘支持 KBP"这一声明具有规范性效力。权威的线上合约见 [`../protocol/README.md`](../protocol/README.md)；本文档告诉键盘作者**需要构建什么**，[`checklist.md`](checklist.md) + [`conformance_tool.py`](conformance_tool.py) 告诉他们**如何验证**。

你可以在任意固件栈和任意 BLE 库上实现 KBP——KBP 仅由空中传输的内容定义。下面的注释在有帮助时会指出 ZMK 的参考路径，但此处没有任何内容要求使用 ZMK。

## 0. 前提条件：键盘必须拥有主机 BLE 链路（central 角色）

KeyBeacon 通过键盘的**面向主机的 BLE 连接**将状态上报给桌面主机。因此键盘必须是主机所连接的设备：

- **一体式 / 单 MCU 键盘**：它本身就是主机链路设备——无需特别处理。
- **分体键盘**：只有持有 **central（主机链路）角色**的半边才暴露 KeyBeacon。副手半边和任何 `settings_reset`/恢复镜像**不得**包含它。（在 ZMK 参考实现中，这意味着 KeyBeacon kit 仅对 central 构建生效。）

如果你的键盘无法充当主机链路 BLE 设备，则它无法按规范实现 KBP。

## 1. 暴露服务与特征

添加一个包含一个**状态特征**的自定义 GATT **主服务**：

| 项目 | 值 |
|------|---|
| 服务 UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` |
| 状态特征 UUID | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` |
| 属性 | `READ` **与** `NOTIFY` |
| 描述符 | 客户端特征配置（CCC，`0x2902`）——NOTIFY 所必需 |

**服务 UUID 即是身份标识和兼容性信号**。不要基于设备名称或型号来控制行为。（由工具检查项 **C1** 验证。）

## 2. 生产状态载荷（≥ 2 字节，小端序）

特征值是来自协议 §4 的可变长度快照：

| 偏移 | 大小 | 字段 | 来源 |
|------|------|------|------|
| `[0]` | 1 | `layer_index`（`uint8`） | 最高激活层索引 |
| `[1]` | 1 | `mods`（`uint8`） | 按住的 HID 修饰键位掩码（见 §4.1） |
| `[2..N]` | ≥ 0 | `layer_name`（UTF-8，无尾部 NUL） | 当前激活层的名称；MAY 为空 |

规则：

- 载荷 MUST **至少为 2 字节**。`layer_name` MAY 为空（2 字节载荷是合法的）。
- `layer_name` MUST 是**有效的 UTF-8** 且**无尾部 NUL**。
- 从键盘权威的键映射/HID 状态派生所有内容——绝不使用第二份缓存副本。
- 将整个快照控制在你协商的 ATT MTU 范围内（参考固件将 `layer_name` 截断至 32 字节；这是实现限制，不是协议限制）。

（由工具检查项 **C2** 验证。）

## 3. 变化时通知，未变化时抑制

- 当快照变化时（层切换或修饰键按下/松开），发送 **NOTIFY**。
- 当重新计算的快照与上次发送的相同时，**抑制**通知。空闲键盘 MUST 产生**零**通知流量。
- 支持 **READ** 以获取当前快照（主机连接时读取一次，然后订阅）。

（由工具检查项 **C3** 验证：订阅成功，空闲时无流量到达。）

## 4. 连接期间保持可发现性

已连接的 BLE HID 键盘会停止广播，因此主机通过**枚举已连接外设**并通过 GATT 确认服务来找到它。只要在**已连接**镜像上暴露服务，你就自动满足此要求——确保服务存在于连接镜像中即可。（连接测试主机时由工具检查项 **C4** 验证。）

## 5. 广播 GAP 设备名称（推荐）

广播非空的 **GAP 设备名称**；主机用它作为显示名称。若缺失，主机回退到通用标签并仍然连接，因此这是**推荐而非必需**。（由工具检查项 **C5** 报告；工具会打印发现的名称供你确认身份。）

## 6. 用一致性工具进行验证

在你的键盘上运行自测（先将键盘连接到测试 Mac 以走可靠路径）：

```bash
python3 conformance/conformance_tool.py            # 默认：--timeout 15 --observe 4
```

工具仅通过**服务 UUID** 发现你的键盘，打印发现的 GAP 名称，并对 C1–C6 逐项报告 **PASS/FAIL/WARN**（见 [`checklist.md`](checklist.md)）。

**退出码：**

| 码 | 含义 |
|----|------|
| `0` | 所有必需项通过——键盘符合 KBP 1.x |
| `1` | 某必需一致性项失败（输出会指明是哪一项） |
| `2` | 环境错误——蓝牙关闭、未找到键盘、连接超时或缺少依赖 |

必需项为 **C1–C4**；**C5** 为推荐项（仅 WARN）；**C6**（分体键盘 central-only）是主机无法观测的**人工固件配置检查**。干净的参考键盘应退出 `0`。

## 7. 工具运行要求

主入口是跨平台工具 `conformance_tool.py`（基于 `bleak`，macOS 12+ / BlueZ 5.56+ / Windows 10+）；
macOS 专用的 PyObjC legacy 工具保留为 `conformance_tool_macos.py`，仅用于 KBP 1.0 回归与
`bleak` 不可用时的 fallback。

```bash
# 主入口（推荐）：跨平台 bleak
python3 -m pip install -U -r conformance/requirements.txt
python3 conformance/conformance_tool.py              # 覆盖 C1–C12

# macOS 回退：PyObjC/CoreBluetooth，仅 KBP 1.0
pip install pyobjc-framework-CoreBluetooth
python3 conformance/conformance_tool_macos.py         # 覆盖 C1–C6
```

macOS 提示时授予终端/应用蓝牙权限。

## 8. A 组字段（KBP 1.1）

KBP 1.1 在 `AA440AA0-…` 同一服务下 **新增两个可选特征**。你的固件 可 实现其一、二者皆实现或都
不实现；不识别的主机不渲染这些字段，1.0 主机像以前一样只看到 1.0 特征。本节是协议 §14 的实施
指引对应物；线上契约以 protocol/README.md 为准。

### §8.1 字段 → 特征映射

| 字段 | KBP 1.1 特征 | 字节位置 | 能力位 |
|------|-------------|---------|-------|
| `is_split` | Connectivity | byte 0 bit 0 | ——（声明于此） |
| `host_state.connected` + `last_disconnect_reason` | Connectivity | byte 1 | `has_host_connection`（bit 1） |
| `profile_index` + `profile_open` + `profile_max_slots` | Connectivity | bytes 2–3 | `has_profile`（bit 2） |
| `split_link_flags`（left_online + right_online） | Connectivity | byte 4 | `has_split_link`（bit 3，要求 `is_split`） |
| `output_endpoint` | Connectivity | byte 5 | `has_output_endpoint`（bit 4） |
| `charging_flags.bit 0`（左半或整板充电） | Connectivity | byte 6 bit 0 | `has_left_charging`（bit 5） |
| `charging_flags.bit 1`（右半充电，仅分体） | Connectivity | byte 6 bit 1 | `has_right_charging`（bit 6，要求 `is_split` + `has_left_charging`） |
| `overall_battery_percent`（整板） | Battery | byte 0（1 字节载荷） | （以特征存在性声明支持） |
| `left_battery_percent` + `right_battery_percent`（分体） | Battery | bytes 0 + 1（2 字节载荷） | （以特征存在性 + `is_split` 声明分体布局） |

`capability_bits` 字段（Connectivity byte 0）是**按字段**的支持声明。某位置为 `0` 意味主机 必须
对该字段 UI **整个隐藏**（对齐治理原则"Observable Degradation Over Guessing"），必须 不渲染
"N/A"、"0" 或任何占位。

### §8.2 capability_bits 布局（Connectivity byte 0）

| 位 | 掩码 | 名称 | 含义 |
|----|------|------|------|
| 0 | `0x01` | `is_split` | 该键盘为分体（ZMK：`CONFIG_ZMK_SPLIT`） |
| 1 | `0x02` | `has_host_connection` | `host_state` 字节有效 |
| 2 | `0x04` | `has_profile` | profile 字段有效 |
| 3 | `0x08` | `has_split_link` | split-link 位有效（要求 bit 0） |
| 4 | `0x10` | `has_output_endpoint` | `output_endpoint` 有效 |
| 5 | `0x20` | `has_left_charging` | 左/整板 `charging_flags.bit 0` 有效 |
| 6 | `0x40` | `has_right_charging` | 右 `charging_flags.bit 1` 有效（要求 `is_split` + `has_left_charging`；整板 必须 发 0） |
| 7 | `0x80` | 保留 | 1.1 固件 必须 发 0 |

### §8.3 固件实现路线图（ZMK 参考，非规范性）

如果你基于 ZMK 构建，下面是每个字段最自然的事件 / API 钩子。`zmk-keybeacon` 外部模块提供了
拎来即用的实现；API 名随 ZMK 版本可能变化，构建时请核对 ZMK main。

| KBP 1.1 字段 | ZMK 事件 / API 钩子 |
|-------------|------------------|
| `is_split` 位 | `IS_ENABLED(CONFIG_ZMK_SPLIT) && IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)`（编译期） |
| `host_state.connected` | 订阅 `zmk_ble_active_profile_changed`；读 `zmk_ble_active_profile_is_connected()` |
| `profile_index` + `profile_open` + `profile_max_slots` | `zmk_ble_active_profile_index()`、`zmk_ble_active_profile_is_open()`、`ZMK_BLE_PROFILE_COUNT` |
| `split_link_flags` | 订阅 `zmk_split_bt_peripheral_status_changed`；读 `zmk_split_bt_peripherals_connected()` |
| `output_endpoint` | 订阅 `zmk_endpoint_changed`；读 `zmk_endpoints_selected()`（映射 USB_HID → 1，BLE → 2） |
| `charging_flags.bit 0`（左/整板） | 可选：板级 charger GPIO（多数板不实现） |
| `charging_flags.bit 1`（右，分体） | 可选：peripheral 侧 charger GPIO 经分体同步总线上报（仅 split central） |
| `overall_battery` / `left_battery` / `right_battery` | 订阅 `zmk_battery_state_changed` + `zmk_peripheral_battery_state_changed`；在 central 侧聚合 |

**节流规则**（固件 必须 遵守）：

- **状态性字段**（host_state、profile、split_link、output_endpoint、charging_flags）：变化即发，
  **无最小间隔**；继承 KBP 1.0 的"snapshot 未变不发"抑制规则（字节一致的 snapshot ⇒ 抑制 NOTIFY）。
- **数值性字段**（电量百分比）：相对上次已发送变化 **≥ 1** 或距上次发送 **≥ 1 秒** 时才发
  （或 关系）；同样继承 snapshot 未变抑制规则。

### §8.4 Legacy macOS 工具与跨平台工具的分工

| | `conformance_tool.py`（主） | `conformance_tool_macos.py`（legacy） |
|---|---------------------------|-----------------------------------------|
| 平台 | macOS 12+、Linux（BlueZ 5.56+）、Windows 10+ | 仅 macOS 12+ |
| BLE 后端 | `bleak>=0.21` | PyObjC + CoreBluetooth |
| KBP 覆盖 | KBP 1.0（C1–C6） + KBP 1.1（C7–C12） | 仅 KBP 1.0（C1–C6） |
| JSON 支持矩阵 | 是（`--json`） | 否 |
| 角色 | 主入口 + CI 目标 | 回归比对；`bleak` 不可用时的 fallback |

legacy 工具除顶部注释指向主工具外**保持不动**。**不要**在那里添加新功能（包括 KBP 1.1 检查），
应添加到 `conformance_tool.py`。

### §8.5 如何验证

```bash
python3 -m pip install -U -r conformance/requirements.txt
python3 conformance/conformance_tool.py --json | tee /tmp/kbp11_matrix.json

# 示例 JSON 断言：
jq '.declared_minor' /tmp/kbp11_matrix.json              # "1.0" 或 "1.1"
jq '.capability_bits.is_split' /tmp/kbp11_matrix.json    # bool，1.1 下存在
jq '.field_support.left_charging' /tmp/kbp11_matrix.json # "supported" | "unsupported" | ...
jq '.exit_code' /tmp/kbp11_matrix.json                   # 0 = 符合
```

JSON schema 以 `spec_version = "kbp-conformance-cli/1"` 固定在工具输出中。
