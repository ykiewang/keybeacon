# KeyBeacon Protocol (KBP)

**Version**: 1.0.0 · **License**: MIT · **Status**: Released standard

> **What this is**: KeyBeacon is an open, implementation-neutral protocol by which a keyboard
> reports its **live internal state the host cannot otherwise know** — the active layer and the
> held modifier keys — to a desktop application over BLE. This document is the single source of
> truth for that interface; a keyboard and an app that both follow it interoperate with no shared
> code.
>
> **Home & scope**: This is the authoritative, independently-versioned `protocol/` module of the
> KeyBeacon app repository. It is self-contained: it depends on no application source and no
> firmware-repo-internal files, so a third party can implement a conforming keyboard or host from
> this document alone. It may be referenced by tag, vendored as a pinned snapshot, or extracted to
> a neutral repository without change.

This specification uses MUST / SHOULD / MAY per RFC 2119. The keyboard is the **producer**; the
desktop app is the **consumer**. Normative sections describe the wire contract only; vendor- and
OS-specific notes are clearly marked **non-normative**.

---

## 1. Transport

A keyboard exposes one custom BLE GATT **primary service** containing one **status
characteristic**:

| Item | Value |
|------|-------|
| Service UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` |
| Status characteristic UUID | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` |
| Characteristic properties | `READ` \| `NOTIFY` |
| Descriptor | Client Characteristic Configuration (CCC) |
| Permission | readable |

The service UUID is also the **protocol-compatibility identifier** — see §8 (Versioning).

## 2. Discovery & identification

- A device is a **KeyBeacon keyboard** if and only if it exposes the service UUID above. A host
  MUST NOT use the device name, make, or model as a compatibility test.
- A connected BLE HID keyboard **stops advertising**, so a host MUST discover it by **enumerating
  already-connected peripherals** (filtering on the KeyBeacon service and, as an aid, the HID
  service `0x1812`) rather than by scanning. After connecting, the host MUST confirm the service
  via GATT service discovery. Active scanning MAY be used only for a keyboard not yet connected
  to the host.
- A device that does not expose the service after discovery MUST NOT be treated as compatible,
  even if it is a keyboard.

## 3. Keyboard identity (name)

- The keyboard's human-readable **display name is its BLE GAP device name**. It is obtained once
  at discovery/connection and is NOT part of the status payload.
- A host MUST render the GAP name when present and non-empty; when it is absent/empty, the host
  MUST show a generic fallback (e.g. `Keyboard <short-identifier>`) and still connect.
- A host MUST NOT maintain a registry/whitelist of models; identity comes only from the service
  (compatibility) and the GAP name (display).

## 4. Status payload

The status characteristic value is a **variable-length, little-endian** snapshot:

| Offset | Size | Field | Meaning |
|--------|------|-------|---------|
| `[0]` | 1 | `layer_index` | Active layer index, `uint8`. Debug/fallback; hosts primarily show the name. |
| `[1]` | 1 | `mods` | Held-modifier bitmask, `uint8` (HID layout below). |
| `[2..N]` | ≥ 0 | `layer_name` | Active layer name, UTF-8, **no trailing `NUL`**. Length = total − 2. |

The payload MUST be at least 2 bytes. `layer_name` MAY be empty.

### 4.1 Modifier bitmask (`mods`)

Standard HID modifier byte:

| Bit | Mask | Key | Bit | Mask | Key |
|-----|------|-----|-----|------|-----|
| 0 | `0x01` | Left Control | 4 | `0x10` | Right Control |
| 1 | `0x02` | Left Shift | 5 | `0x20` | Right Shift |
| 2 | `0x04` | Left Alt | 6 | `0x40` | Right Alt |
| 3 | `0x08` | Left Gui | 7 | `0x80` | Right Gui |

A host SHOULD merge left/right into four logical indicators:

| Indicator | Active when any bit set |
|-----------|-------------------------|
| Shift | `0x02 \| 0x20` |
| Control | `0x01 \| 0x10` |
| Alt | `0x04 \| 0x40` |
| Gui | `0x08 \| 0x80` |

## 5. Behavior

- **READ** returns the current snapshot (used as the initial value on connect).
- **NOTIFY** is sent only when the snapshot **changes** (layer or modifier change); the producer
  MUST suppress notifications when the recomputed snapshot equals the last-sent one. An idle
  keyboard therefore produces zero traffic.
- The consumer enables notifications via the CCC; on reconnect it re-READs and re-subscribes.

## 6. Worked examples

**Example A — layer `SYM` (index 2), holding Left Shift + Right Shift**

- `layer_index = 0x02`, `mods = 0x02 | 0x20 = 0x22`, `layer_name = "SYM" = 53 59 4D`

```
┌──────┬──────┬────────────────┐
│ 0x02 │ 0x22 │ 53 59 4D       │   → "SYM", Shift indicator ON (others off)
└──────┴──────┴────────────────┘
 layer   mods   "S" "Y" "M"
```

**More snapshots**

| State | Bytes (hex) | Host shows |
|-------|-------------|------------|
| `BASE` (0), no modifiers | `00 00 42 41 53 45` | "BASE", all indicators dim |
| `NAVI` (1), Left Control only | `01 01 4E 41 56 49` | "NAVI", Control ON |
| Layer 2 with **no name** | `02 00` | fallback "L2" |
| (malformed) 1-byte value | `02` | discarded (payload < 2 bytes) |

## 7. Consumer (host) rules

1. Reject payloads shorter than 2 bytes.
2. Decode `layer_name` as UTF-8; if empty or undecodable, display `L{layer_index}`.
3. Merge modifier halves per §4.1.
4. Treat the absence of a live subscription as *not connected*; never display stale state as
   current.
5. Identify and remember a specific keyboard by its stable connection identifier, not by name
   (names are not unique).

## 8. Producer (firmware) rules

1. Derive all reported state from the keyboard's authoritative keymap/HID sources (never a
   second, cached copy).
2. Report state the host cannot cheaply obtain itself (the active layer is the canonical case).
3. Emit no notification when the recomputed snapshot equals the last-sent snapshot.
4. Expose the feature from the role that owns the host BLE link (for split keyboards, the
   central half) and nowhere else.

## 9. Versioning & compatibility

KeyBeacon is versioned with semantic versioning, and compatibility is detectable **on the wire**:

- **MAJOR (breaking)** — reinterpreting existing byte positions or changing identifiers. A MAJOR
  revision MUST use a **new service UUID**. Hosts recognize the set of service UUIDs they
  support; a keyboard exposing only an unknown (newer/incompatible) service is cleanly reported
  as *unsupported* rather than mis-parsed.
- **MINOR (additive)** — appending new **reserved trailing bytes** after `layer_name`, or adding
  a new optional characteristic/descriptor. The service UUID is unchanged; old hosts ignore the
  tail and keep working.
- **PATCH** — clarifications with no wire change.

KBP `1.x` is the service UUID `AA440AA0-…` with the payload of §4. There is no explicit version
field in the v1 payload; the service UUID *is* the MAJOR-version signal.

## 10. Conformance checklist

A keyboard conforms to KBP 1.x when all of the following hold (these are the checks a conformance
tool automates):

1. Exposes service `AA440AA0-…` with characteristic `AA440AA1-…` (`READ`+`NOTIFY`, CCC present).
2. READ returns a snapshot ≥ 2 bytes matching §4; `layer_name` is valid UTF-8 or empty.
3. NOTIFY fires on layer/modifier change and is suppressed when the snapshot is unchanged.
4. Remains discoverable while connected via connected-peripheral enumeration (it stops
   advertising once connected).
5. Advertises a non-empty GAP device name (RECOMMENDED; else the host uses a generic fallback).
6. For split keyboards: the feature is present only on the central (host-link) role and absent
   from secondary and reset images.

## 11. Reserved / future extensions (non-normative)

- A dedicated **read-once "keyboard name" characteristic**, for keyboards needing a display name
  distinct from their GAP name. Additive (MINOR); same service UUID.
- Additional reserved trailing payload fields (e.g., profile/output indicators) — additive only.

## 12. Reference implementation notes (non-normative)

- **ZMK firmware**: the snapshot maps to `zmk_keymap_highest_layer_active()` (→ `[0]`),
  `zmk_hid_get_explicit_mods()` (→ `[1]`), and `zmk_keymap_layer_name(layer_index_to_id(idx))`
  (→ `[2..]`). The feature is gated by `CONFIG_ZMK_KEYBEACON` + `ZMK_BLE` + central role. A
  reference keyboard implements this as a shield-scoped kit so it can reach ZMK private headers.
- **Firmware name-length note**: a reference firmware truncates `layer_name` to 32 bytes so a
  snapshot fits the default ATT MTU. This is an implementation limit, **not** a protocol limit.
- **macOS host**: discovery uses CoreBluetooth `retrieveConnectedPeripherals(withServices:)`
  (connected HID keyboards stop advertising); the display name is `CBPeripheral.name`; the stable
  remember-key is `CBPeripheral.identifier`.

## 13. Changelog

- **1.1.0** — KBP 1.1 (MINOR): adds two optional characteristics `AA440AA2-…`
  (Connectivity: capability bits + host-state + profile + split-link + output
  endpoint + per-half charging flags) and `AA440AA3-…` (Battery: overall or
  per-half percent); service UUID and the `AA440AA1-…` payload are unchanged.
  See §14 and `CHANGELOG.md` 1.1.0.
- **1.0.0** — Initial KeyBeacon Protocol: BLE GATT service/characteristic, service-UUID
  identification, GAP-name identity, `[layer_index][mods][layer_name]` payload, READ/NOTIFY with
  change suppression, conformance checklist, and UUID-based MAJOR versioning. Consolidates the
  feature-001 status-snapshot contract and the feature-002 discovery-and-identity amendment.

## 14. KBP 1.1 Connectivity & Power (optional)

**Added in KBP 1.1 (MINOR).** The service UUID is unchanged at `AA440AA0-…`;
the KBP 1.0 characteristic `AA440AA1-…` is **completely untouched**. KBP 1.1
introduces **two new optional characteristics** that a keyboard MAY expose to
describe its live connectivity and battery state. A host that does not
recognise these characteristics ignores them and keeps working as a KBP 1.0
host.

### 14.1 Scope & version

- **KBP MAJOR**: 1 (service UUID `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` **unchanged**).
- **KBP MINOR**: bumped to **1.1**.
- **Breaking changes**: none. The KBP 1.0 characteristic `AA440AA1-…` is **unchanged**.
- Backward-compatibility guarantees:
  - A KBP 1.0 host (subscribes to `AA440AA1-…` only) connecting to a KBP 1.1
    keyboard → the 1.1 characteristics are not subscribed, firmware emits no
    notifications on them, and the behaviour degrades cleanly to 1.0.
  - A KBP 1.1 host connecting to a KBP 1.0 keyboard → GATT discovery does not
    find the new characteristics, the host MUST **hide the entire 1.1 UI**,
    and all other behaviour is identical to 1.0.

### 14.2 The two new characteristics

| Item | Connectivity characteristic | Battery characteristic |
|------|------------------------------|------------------------|
| UUID | `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` | `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` |
| Properties | `READ` \| `NOTIFY` | `READ` \| `NOTIFY` |
| Descriptor | Client Characteristic Configuration (CCC, `0x2902`) | Client Characteristic Configuration (CCC, `0x2902`) |
| Carries | all state-ish fields + capability bits | battery percent (overall or per half) |
| notify throttling | emit-on-change (state-ish) | ≥ 1 pp change **OR** ≥ 1 s since last emit (numeric) |
| Optional | yes — whole characteristic MAY be absent if firmware implements no 1.1 optional fields | yes — whole characteristic MAY be absent if firmware does not report battery |

Both characteristics live under the **same** primary service as KBP 1.0
(`AA440AA0-…`); the producer MUST NOT introduce a new service for 1.1.

### 14.3 Connectivity characteristic payload

#### 14.3.1 Layout (little-endian, **fixed length ≥ 7 bytes**)

| Offset | Size | Field | Range / encoding |
|--------|------|-------|------------------|
| `[0]` | 1 | `capability_bits` | uint8, per-bit meaning in §14.3.2 |
| `[1]` | 1 | `host_state` | bit 0: `connected`; bits 1–2: `last_disconnect_reason` (0 unknown / 1 explicit / 2 timeout / 3 reserved); bits 3–7 reserved (1.1 firmware MUST emit 0) |
| `[2]` | 1 | `profile_index` | bits 0–6: 1-based index (0 = field not applicable); bit 7: `profile_open` (1 = open, waiting-to-pair) |
| `[3]` | 1 | `profile_max_slots` | uint8, firmware-declared max slot count (0 = field not applicable) |
| `[4]` | 1 | `split_link_flags` | bit 0: left_online; bit 1: right_online; bits 2–7 reserved (1.1 MUST emit 0) |
| `[5]` | 1 | `output_endpoint` | 0 = unknown / 1 = USB / 2 = BLE / 3–255 reserved (future use) |
| `[6]` | 1 | `charging_flags` | bit 0: left_charging (overall when `is_split = 0`, **requires** `has_left_charging = 1`); bit 1: right_charging (**requires** `is_split = 1` **and** `has_right_charging = 1`; firmware MUST emit 0 when `is_split = 0`); bits 2–7 reserved |
| `[7..N]` | ≥ 0 | reserved trailing bytes | future MINOR fields; **producer** emits 0 bytes in 1.1 (payload is exactly 7 bytes); **consumer** MUST ignore the tail |

#### 14.3.2 `capability_bits` (byte 0)

| Bit | Mask | Name | Meaning |
|-----|------|------|---------|
| 0 | `0x01` | `is_split` | the keyboard is a split (ZMK reference binds to `CONFIG_ZMK_SPLIT`) |
| 1 | `0x02` | `has_host_connection` | `host_state` field is meaningful |
| 2 | `0x04` | `has_profile` | `profile_index` + `profile_max_slots` are meaningful |
| 3 | `0x08` | `has_split_link` | `split_link_flags` is meaningful; **requires** bit 0 = 1 |
| 4 | `0x10` | `has_output_endpoint` | `output_endpoint` is meaningful |
| 5 | `0x20` | `has_left_charging` | `charging_flags.bit 0` is meaningful (overall when integer board) |
| 6 | `0x40` | `has_right_charging` | `charging_flags.bit 1` is meaningful; **requires** bit 0 = 1 (`is_split = 1`); firmware MUST emit 0 when `is_split = 0` |
| 7 | `0x80` | reserved | 1.1 firmware MUST emit 0 |

#### 14.3.3 Producer invariants (firmware MUST)

- **P-C1**: if `has_split_link = 1`, then `is_split = 1`.
- **P-C2**: for any field whose capability bit = 0, firmware MAY emit 0 bytes; consumers MUST ignore the specific value.
- **P-C3**: `profile_index` bits 0–6 ≤ `profile_max_slots` (index MUST NOT be out of range).
- **P-C4**: 1.1 firmware MUST emit 0 for all reserved positions (byte 1 bits 3–7, byte 4 bits 2–7, byte 6 bits 2–7, byte 0 bit 7, byte 7+).
- **P-C5**: if `has_right_charging = 1`, then `has_left_charging = 1` **and** `is_split = 1`; on an integer board (`is_split = 0`), both `has_right_charging` and `charging_flags.bit 1` MUST be 0.

#### 14.3.4 Consumer rules (host MUST)

- **C-C1**: payload length **< 7 bytes** → drop entire frame, log a structured diagnostic, do **not** update UI.
- **C-C2**: payload length **≥ 7 bytes** → consume bytes 0..6, ignore bytes 7+ (ensures MINOR forward-compatibility).
- **C-C3**: if `capability_bits.has_split_link = 1` but `is_split = 0`, host MUST treat `has_split_link` as 0 (firmware bug) and log a `capability.inconsistent` diagnostic.
- **C-C4**: if `profile_index` bits 0–6 > `profile_max_slots`, host MUST clamp the UI-displayed index to `profile_max_slots` and log a `profile.out_of_range` diagnostic.
- **C-C5**: for `output_endpoint` reserved values 3–255, host MUST display "unknown endpoint (0x__)" rather than crashing.
- **C-C6**: if `has_right_charging = 1` but `is_split = 0`, host MUST treat `has_right_charging` as 0 (firmware bug), log a `capability.inconsistent` diagnostic, and MUST NOT render the right-half charging icon.
- **C-C7**: if `has_left_charging = 0` but `charging_flags.bit 0` is non-zero, host MUST ignore the bit value and log a `capability.inconsistent` diagnostic (bit 1 similarly).

#### 14.3.5 Notify throttling (producer MUST)

- Any state-ish bit flip or enum value change → notify the current snapshot **immediately**.
- Inherit KBP 1.0 §5 "snapshot-unchanged suppression": firmware MUST suppress notification when the recomputed snapshot equals the last-sent snapshot byte-for-byte.

### 14.4 Battery characteristic payload

#### 14.4.1 Layout (little-endian, **length varies with `is_split`**)

| Case (from `capability_bits.is_split`) | payload length | bytes |
|------|------|------|
| `is_split = 0` (integer board) | **1 byte** | `[0]` = `overall_battery_percent` (uint8) |
| `is_split = 1` (split) | **2 bytes** | `[0]` = `left_battery_percent`, `[1]` = `right_battery_percent` (each uint8) |

#### 14.4.2 Battery percent (uint8 encoding)

| Value range | Meaning |
|------|------|
| `0..100` | normal percent |
| `101..254` | reserved |
| `255` | sentinel: read failed / temporarily unavailable (e.g., brief I²C loss) |

#### 14.4.3 Producer invariants (firmware MUST)

- **P-B1**: payload length strictly matches `is_split` (do not emit 0 bytes, do not emit 3+ bytes).
- **P-B2**: firmware **passes raw readings through**; MUST NOT perform smoothing / sliding average at the firmware layer, to prevent masking a transient failure as a "normal low battery".
- **P-B3**: if firmware cannot report battery at all → the entire Battery characteristic MUST NOT be exposed (GATT discovery simply doesn't find it).

#### 14.4.4 Consumer rules (host MUST)

- **C-B1**: if `capability_bits.is_split = 0` and payload ≠ 1 byte → drop and log `battery.length_mismatch`.
- **C-B2**: if `is_split = 1` and payload ≠ 2 bytes → drop and log `battery.length_mismatch`.
- **C-B3**: byte value ∈ [0, 100] → display percent; = 255 → display "read failed"; 101–254 → display "read failed" and log `battery.out_of_range`.
- **C-B4**: host MAY apply a ≤ 3 s sliding average to the rendered value, but MUST NOT affect SC-003 judgement (i.e., diagnostic logs preserve the raw byte).

#### 14.4.5 Notify throttling (producer MUST)

Numeric-field throttling, **OR** relation:

- Condition A: raw byte value changes by ≥ 1 relative to last-sent (i.e., ≥ 1 percentage point).
- Condition B: ≥ 1 second has elapsed since this field was last notified.

**A ∨ B** holds → notify. Inherit KBP 1.0 §5 "snapshot-unchanged suppression" (byte-for-byte identical snapshots suppress notification).

### 14.5 Discovery & subscription (consumer flow)

- Service discovery remains per KBP 1.0 §2: enumerate connected peripherals via `retrieveConnectedPeripherals(withServices: [HID, KBPService])`, confirm `AA440AA0-…` present over GATT.
- After the service is confirmed, consumers MUST request discovery of **all** characteristics under that service and determine the keyboard's declared KBP MINOR from characteristic UUID **presence**:
  - Only `AA440AA1-…` found → 1.0 only; consumer MUST NOT render 1.1 UI.
  - `AA440AA1-…` + `AA440AA2-…` found → 1.1 Connectivity fields are supported; also check `AA440AA3-…` to decide battery UI.
  - `AA2` found but `AA1` missing → anomaly; host MUST log `discovery.anomaly` and fall back to 1.0-only behaviour (never trust 1.1 fields on an incompatible wire).
- On every reconnect, consumer MUST re-READ and re-CCC-subscribe each new characteristic it had previously subscribed to.

### 14.6 Version signal & upgrade path

- Unchanged service UUID means KBP 1.0 / 1.1 are **wire-detectably equivalent**; MINOR distinction is determined by characteristic presence.
- Future KBP 1.2+ MUST follow the same strategy: **append new characteristics** or **append reserved trailing bytes to Connectivity** (per README §9 MINOR rule).
- Any change that reinterprets existing byte positions or modifies UUIDs is **MAJOR** and MUST follow the service-UUID-replacement path.

### 14.7 Extension of the §10 conformance checklist

This section introduces the following new conformance items (implemented in
`conformance/checklist.md` as C7–C12; see `conformance/CONFORMANCE.md`):

- **C7**: if `AA440AA2-…` is present → properties = `READ`+`NOTIFY`, with CCC.
- **C8**: Connectivity READ returns ≥ 7 bytes; each field satisfies §14.3 and invariants P-C1..P-C5.
- **C9**: if `AA440AA3-…` is present → properties = `READ`+`NOTIFY`, with CCC, and payload length matches `is_split`.
- **C10**: state-ish field changes trigger NOTIFY; snapshot-unchanged suppression applies.
- **C11**: numeric-field throttling satisfies §14.4.5 (≥ 1 pp **OR** ≥ 1 s, OR relation).
- **C12**: 1.1 characteristics are exposed only by the central role of a split keyboard (extends §8.4 "feature from central only" to 1.1).

### 14.8 Firmware reference mapping (non-normative, ZMK)

| KBP 1.1 field | ZMK reference source |
|------|------|
| `is_split` bit | `IS_ENABLED(CONFIG_ZMK_SPLIT) && IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)` |
| `host_state.connected` | `zmk_ble_active_profile_is_connected()` + subscribe `zmk_ble_active_profile_changed` |
| `profile_index` + `profile_open` + `profile_max_slots` | `zmk_ble_active_profile_index()`, `zmk_ble_active_profile_is_open()`, `ZMK_BLE_PROFILE_COUNT` |
| `split_link_flags` | subscribe `zmk_split_bt_peripheral_status_changed`; read `zmk_split_bt_peripherals_connected()` |
| `output_endpoint` | subscribe `zmk_endpoint_changed`; read `zmk_endpoints_selected()` (map USB_HID → 1, BLE → 2) |
| `charging_flags.bit 0` (`has_left_charging`) | optional board-local charger GPIO (overall when integer board; most boards do not implement) |
| `charging_flags.bit 1` (`has_right_charging`) | optional peripheral-side charger GPIO reported via split sync bus (split central only) |
| `overall_battery` / `left_battery` / `right_battery` | subscribe `zmk_battery_state_changed` + `zmk_peripheral_battery_state_changed`; central-side aggregation |

API names may evolve across ZMK releases; the implementation phase (`zmk-keybeacon` module) MUST verify against ZMK main at build time.

---

# KeyBeacon 协议（KBP）— 中文版

**English** · [中文](#zh-kbp)

<a id="zh-kbp"></a>

**版本**：1.0.0 · **许可**：MIT · **状态**：已发布标准

> **本文档是什么**：KeyBeacon 是一个开放的、与实现无关的协议。通过该协议，键盘可将**主机无法直接
> 获知的活跃内部状态**——当前激活的层与按住的修饰键——通过 BLE 上报给桌面应用。本文档是该接口的
> 唯一真相源；只要键盘与应用都遵循本协议，二者无需共享代码即可互操作。
>
> **归属与范围**：本文档是 KeyBeacon 应用仓库中权威的、独立版本化的 `protocol/` 模块。它是自包含
> 的，不依赖任何应用源码或固件仓库内部文件，因此第三方仅凭本文档即可实现合规的键盘端或主机端。本文档
> 可通过标签引用、作为固定快照 vendored，或单独提取至独立仓库，内容不变。

本规范中 MUST / SHOULD / MAY 的含义遵循 RFC 2119。键盘为**生产者**；桌面应用为**消费者**。规范
性章节仅描述线上合约；厂商与操作系统相关的注释均明确标注为**非规范性**。

---

## §1. 传输层

键盘暴露一个包含一个**状态特征**的自定义 BLE GATT **主服务**：

| 项目 | 值 |
|------|---|
| 服务 UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` |
| 状态特征 UUID | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` |
| 特征属性 | `READ` \| `NOTIFY` |
| 描述符 | 客户端特征配置（CCC） |
| 权限 | 可读 |

服务 UUID 同时也是**协议兼容性标识符**——详见 §9（版本与兼容性）。

## §2. 发现与身份识别

- 当且仅当设备暴露上述服务 UUID 时，该设备才是 **KeyBeacon 键盘**。主机 MUST NOT 以设备名称、
  品牌或型号作为兼容性判断依据。
- 已连接的 BLE HID 键盘**会停止广播**，因此主机 MUST 通过**枚举已连接外设**（按 KeyBeacon 服务
  过滤，辅以 HID 服务 `0x1812`）来发现键盘，而非扫描广播包。连接后，主机 MUST 通过 GATT 服务
  发现来确认服务存在。仅当键盘尚未连接至主机时，主动扫描 MAY 被使用。
- 发现后若设备未暴露该服务，MUST NOT 将其视为兼容设备，即便它是键盘。

## §3. 键盘身份（名称）

- 键盘的人类可读**显示名称**是其 **BLE GAP 设备名称**。它在发现/连接时获取一次，**不**属于状态
  载荷的一部分。
- 主机 MUST 在 GAP 名称存在且非空时显示它；若不存在或为空，主机 MUST 显示通用占位名（如
  `Keyboard <短标识符>`）并继续连接。
- 主机 MUST NOT 维护任何型号注册表/白名单；身份仅来自服务 UUID（兼容性）与 GAP 名称（显示）。

## §4. 状态载荷

状态特征的值是一个**可变长度、小端序**快照：

| 偏移 | 大小 | 字段 | 含义 |
|------|------|------|------|
| `[0]` | 1 | `layer_index` | 当前激活层索引，`uint8`。调试/回退用；主机优先显示层名称。 |
| `[1]` | 1 | `mods` | 按住的修饰键位掩码，`uint8`（HID 布局见下）。 |
| `[2..N]` | ≥ 0 | `layer_name` | 当前激活层名称，UTF-8 编码，**无尾部 `NUL`**。长度 = 总长 − 2。 |

载荷 MUST 至少为 2 字节。`layer_name` MAY 为空。

### §4.1 修饰键位掩码（`mods`）

标准 HID 修饰字节：

| 位 | 掩码 | 按键 | 位 | 掩码 | 按键 |
|----|------|------|----|------|------|
| 0 | `0x01` | 左 Control | 4 | `0x10` | 右 Control |
| 1 | `0x02` | 左 Shift | 5 | `0x20` | 右 Shift |
| 2 | `0x04` | 左 Alt | 6 | `0x40` | 右 Alt |
| 3 | `0x08` | 左 Gui | 7 | `0x80` | 右 Gui |

主机 SHOULD 将左右两侧合并为四个逻辑指示器：

| 指示器 | 任意对应位置位时激活 |
|--------|---------------------|
| Shift | `0x02 \| 0x20` |
| Control | `0x01 \| 0x10` |
| Alt | `0x04 \| 0x40` |
| Gui | `0x08 \| 0x80` |

## §5. 行为规范

- **READ** 返回当前快照（连接时作为初始值使用）。
- **NOTIFY** 仅在快照**变化**（层切换或修饰键按下/松开）时发送；生产者 MUST 在重新计算的快照
  与上次发送的快照相同时抑制通知。空闲键盘因此不产生任何流量。
- 消费者通过 CCC 启用通知；重新连接时重新 READ 并重新订阅。

## §6. 示例

**示例 A — 层 `SYM`（索引 2），同时按住左 Shift + 右 Shift**

- `layer_index = 0x02`，`mods = 0x02 | 0x20 = 0x22`，`layer_name = "SYM" = 53 59 4D`

```
┌──────┬──────┬────────────────┐
│ 0x02 │ 0x22 │ 53 59 4D       │   → "SYM"，Shift 指示器亮起（其余熄灭）
└──────┴──────┴────────────────┘
 层索引  修饰键  "S" "Y" "M"
```

**更多快照示例**

| 状态 | 字节（十六进制） | 主机显示 |
|------|-----------------|---------|
| `BASE`（0），无修饰键 | `00 00 42 41 53 45` | "BASE"，所有指示器熄灭 |
| `NAVI`（1），仅左 Control | `01 01 4E 41 56 49` | "NAVI"，Control 亮起 |
| 层 2，**无名称** | `02 00` | 回退显示 "L2" |
| （畸形）1 字节值 | `02` | 丢弃（载荷 < 2 字节） |

## §7. 消费者（主机）规则

1. 丢弃长度小于 2 字节的载荷。
2. 以 UTF-8 解码 `layer_name`；若为空或无法解码，则显示 `L{layer_index}`。
3. 按 §4.1 合并修饰键左右两侧。
4. 将无活跃订阅视为*未连接*；永远不将过时状态显示为当前状态。
5. 通过稳定的连接标识符（而非名称）识别并记忆特定键盘。

## §8. 生产者（固件）规则

1. 从键盘权威的键映射/HID 源派生所有上报状态，永不使用第二份缓存副本。
2. 上报主机难以自行廉价获取的状态（当前激活层是典型案例）。
3. 当重新计算的快照与上次发送的快照相同时，不发出通知。
4. 仅在拥有主机 BLE 链路的角色（对于分体键盘，即中央半）上暴露该功能，其他地方均不暴露。

## §9. 版本与兼容性

KeyBeacon 采用语义化版本，兼容性可**在线上检测**：

- **MAJOR（破坏性）** — 重新解释现有字节位置或更改标识符。MAJOR 修订 MUST 使用**新的服务
  UUID**。主机识别其支持的服务 UUID 集合；仅暴露未知（更新/不兼容）服务的键盘将被干净地报告为
  *不受支持*，而非被错误解析。
- **MINOR（向后兼容的新增）** — 在 `layer_name` 之后追加新的**保留尾部字节**，或添加新的可选
  特征/描述符。服务 UUID 不变；旧主机忽略尾部并继续工作。
- **PATCH** — 仅澄清说明，无线上变更。

KBP `1.x` 是服务 UUID `AA440AA0-…` 加上 §4 的载荷。v1 载荷中没有显式版本字段；服务 UUID *即为*
MAJOR 版本信号。

## §10. 一致性检查清单

当以下所有条件均满足时，键盘符合 KBP 1.x（这些是一致性工具自动检查的项目）：

1. 暴露服务 `AA440AA0-…` 及特征 `AA440AA1-…`（`READ`+`NOTIFY`，存在 CCC）。
2. READ 返回满足 §4 格式且 ≥ 2 字节的快照；`layer_name` 为有效 UTF-8 或为空。
3. NOTIFY 在层/修饰键变化时触发，且在快照未变化时被抑制。
4. 已连接时仍可通过已连接外设枚举被发现（停止广播后仍可被连接至主机时发现）。
5. 广播非空 GAP 设备名称（建议；若缺失，主机使用通用占位名）。
6. 对于分体键盘：该功能仅存在于中央（主机链路）角色，副手和重置镜像中均不包含。

## §11. 保留 / 未来扩展（非规范性）

- 专用的**一次性读取"键盘名称"特征**，适用于需要与 GAP 名称不同的显示名称的键盘。向后兼容
  新增（MINOR）；服务 UUID 不变。
- 额外的保留尾部载荷字段（例如配置/输出指示器）——仅向后兼容新增。

## §12. 参考实现说明（非规范性）

- **ZMK 固件**：快照映射到 `zmk_keymap_highest_layer_active()`（→ `[0]`）、
  `zmk_hid_get_explicit_mods()`（→ `[1]`）和
  `zmk_keymap_layer_name(layer_index_to_id(idx))`（→ `[2..]`）。该功能由
  `CONFIG_ZMK_KEYBEACON` + `ZMK_BLE` + 中央角色控制。参考键盘以 shield 范围的套件形式实现，
  以便访问 ZMK 私有头文件。
- **固件名称长度注意事项**：参考固件将 `layer_name` 截断至 32 字节，使快照适配默认 ATT MTU。
  这是实现限制，**不是**协议限制。
- **macOS 主机**：发现使用 CoreBluetooth 的 `retrieveConnectedPeripherals(withServices:)`
  （已连接的 HID 键盘停止广播）；显示名称来自 `CBPeripheral.name`；稳定的记忆键为
  `CBPeripheral.identifier`。

## §13. 变更日志

- **1.1.0** — KBP 1.1（MINOR）：新增两个可选特征 `AA440AA2-…`（Connectivity：能力位 +
  主机状态 + profile + 分体链路 + 输出端点 + 按半充电位）与 `AA440AA3-…`（Battery：
  整板或按半电量百分比）；服务 UUID 与 `AA440AA1-…` 载荷均**不变**。详见 §14 与
  `CHANGELOG.md` 1.1.0。
- **1.0.0** — 初始 KeyBeacon 协议：BLE GATT 服务/特征、基于服务 UUID 的身份识别、GAP 名称
  身份、`[layer_index][mods][layer_name]` 载荷、带变化抑制的 READ/NOTIFY、一致性检查清单，以及
  基于 UUID 的 MAJOR 版本控制。整合了 feature-001 状态快照合约与 feature-002 发现与身份修正。

## §14. KBP 1.1 连接与电量（可选特征）

**KBP 1.1（MINOR）新增**。服务 UUID 保持 `AA440AA0-…` 不变；KBP 1.0 的特征 `AA440AA1-…`
**完全不动**。KBP 1.1 引入**两个新的可选特征**，键盘 可 暴露它们以描述其实时连接与电量
状态。不识别这两个特征的主机忽略它们并继续按 KBP 1.0 主机工作。

### §14.1 范围与版本

- **KBP MAJOR**：1（服务 UUID `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` **不变**）。
- **KBP MINOR**：升至 **1.1**。
- **破坏性变更**：无。KBP 1.0 的特征 `AA440AA1-…` **不变**。
- 向后兼容保证：
  - KBP 1.0 主机（只订阅 `AA440AA1-…`）连接 KBP 1.1 键盘 → 新特征未被订阅，固件不在
    其上发出通知，行为完全退化为 1.0。
  - KBP 1.1 主机连接 KBP 1.0 键盘 → GATT 发现找不到新特征，主机 必须 **整张隐藏 1.1
    UI**，其他行为与 1.0 完全一致。

### §14.2 两个新特征

| 项 | Connectivity 特征 | Battery 特征 |
|---|------------------|-------------|
| UUID | `AA440AA2-F5ED-4C48-84A1-8062D20D3D55` | `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` |
| 属性 | `READ` \| `NOTIFY` | `READ` \| `NOTIFY` |
| 描述符 | 客户端特征配置（CCC，`0x2902`） | 客户端特征配置（CCC，`0x2902`） |
| 承载 | 所有状态性字段 + 能力位 | 电量百分比（整板或按半） |
| notify 节流 | 变即发（状态性） | 变化 ≥ 1 pp **或** 距上次 ≥ 1 秒（数值性） |
| 可选 | 是——若固件不实现任何 1.1 可选字段，整个特征 可 缺省 | 是——若固件不上报电量，整个特征 可 缺省 |

两个特征均位于 KBP 1.0 **同一个** 主服务 `AA440AA0-…` 下；生产者 必须 不新增 service。

### §14.3 Connectivity 特征载荷

#### §14.3.1 布局（小端序，**固定长度 ≥ 7 字节**）

| 偏移 | 大小 | 字段 | 范围 / 编码 |
|------|-----|-----|------------|
| `[0]` | 1 | `capability_bits` | uint8，每位含义见 §14.3.2 |
| `[1]` | 1 | `host_state` | bit 0: `connected`；bits 1–2: `last_disconnect_reason`（0 未知 / 1 主动 / 2 超时 / 3 保留）；bits 3–7 保留（1.1 固件 必须 发 0） |
| `[2]` | 1 | `profile_index` | bits 0–6: 1 起索引（0 = 字段不适用）；bit 7: `profile_open`（1 = open 待配对） |
| `[3]` | 1 | `profile_max_slots` | uint8，固件声明的最大槽位数（0 = 字段不适用） |
| `[4]` | 1 | `split_link_flags` | bit 0: left_online；bit 1: right_online；bits 2–7 保留（1.1 必须 发 0） |
| `[5]` | 1 | `output_endpoint` | 0 = 未知 / 1 = USB / 2 = BLE / 3–255 保留（预留未来扩展） |
| `[6]` | 1 | `charging_flags` | bit 0: left_charging（`is_split = 0` 时为整板，**要求** `has_left_charging = 1`）；bit 1: right_charging（**要求** `is_split = 1` **且** `has_right_charging = 1`；整板时固件 必须 发 0）；bits 2–7 保留 |
| `[7..N]` | ≥ 0 | 保留尾部字节 | 未来 MINOR 的追加字段；**生产者** 在 1.1 发 0 字节（即载荷恰为 7 字节）；**消费者** 必须 忽略尾部 |

#### §14.3.2 `capability_bits`（byte 0）

| 位 | 掩码 | 名称 | 含义 |
|----|------|------|------|
| 0 | `0x01` | `is_split` | 该键盘为分体（ZMK 参考实现绑定 `CONFIG_ZMK_SPLIT`） |
| 1 | `0x02` | `has_host_connection` | `host_state` 字段有效 |
| 2 | `0x04` | `has_profile` | `profile_index` + `profile_max_slots` 有效 |
| 3 | `0x08` | `has_split_link` | `split_link_flags` 有效；**要求** bit 0 = 1 |
| 4 | `0x10` | `has_output_endpoint` | `output_endpoint` 有效 |
| 5 | `0x20` | `has_left_charging` | `charging_flags.bit 0` 有效（整板时为 overall） |
| 6 | `0x40` | `has_right_charging` | `charging_flags.bit 1` 有效；**要求** bit 0 = 1（`is_split = 1`）；整板时固件 必须 发 0 |
| 7 | `0x80` | 保留 | 1.1 固件 必须 发 0 |

#### §14.3.3 生产者不变量（固件 必须 保证）

- **P-C1**：若 `has_split_link = 1`，则 `is_split = 1`。
- **P-C2**：对任一能力位 = 0 的字段，固件 可 填 0 字节；消费者 必须 忽略该字段的具体值。
- **P-C3**：`profile_index` bits 0–6 ≤ `profile_max_slots`（索引 必须 不越界）。
- **P-C4**：1.1 固件 必须 把保留位全部发 0（byte 1 bits 3–7、byte 4 bits 2–7、byte 6 bits 2–7、byte 0 bit 7、byte 7+）。
- **P-C5**：若 `has_right_charging = 1`，则 `has_left_charging = 1` **且** `is_split = 1`；整板键盘（`is_split = 0`）下 `has_right_charging` 必须 = 0 且 `charging_flags.bit 1` 必须 = 0。

#### §14.3.4 消费者规则（主机 必须 保证）

- **C-C1**：载荷长度 **< 7 字节** → 整条丢弃，记一次结构化诊断日志，**不** 更新 UI。
- **C-C2**：载荷长度 **≥ 7 字节** → 消费 byte 0..6，忽略 byte 7+（保证 MINOR 向上兼容）。
- **C-C3**：若 `capability_bits.has_split_link = 1` 但 `is_split = 0`，主机 必须 把 `has_split_link` 当作 0（视为固件 bug），记一次 `capability.inconsistent` 诊断日志。
- **C-C4**：若 `profile_index` bits 0–6 > `profile_max_slots`，主机 必须 把 UI 显示的 index 钳制在 `profile_max_slots` 并记一次 `profile.out_of_range` 诊断日志。
- **C-C5**：对 `output_endpoint` 的 3–255 保留值，主机 必须 显示为"未知端点（0x__）"而非崩溃。
- **C-C6**：若 `has_right_charging = 1` 但 `is_split = 0`，主机 必须 把 `has_right_charging` 当作 0（视为固件 bug），记一次 `capability.inconsistent` 诊断日志，且 必须 不渲染右半充电图标。
- **C-C7**：若 `has_left_charging = 0` 但 `charging_flags.bit 0` 非 0，主机 必须 忽略该位值并记一次 `capability.inconsistent` 诊断日志（bit 1 同理）。

#### §14.3.5 Notify 节流（生产者 必须 保证）

- 状态性字段的任一比特翻转或枚举值变化 → **立即** notify 当前 snapshot。
- 继承 KBP 1.0 §5 "snapshot 未变不发" 抑制规则：固件 必须 在重新计算的 snapshot 与上次发送的 snapshot 字节相等时**抑制**通知。

### §14.4 Battery 特征载荷

#### §14.4.1 布局（小端序，**长度随 `is_split`**）

| 情形（来自 `capability_bits.is_split`） | 载荷长度 | 字节 |
|------|------|------|
| `is_split = 0`（整板） | **1 字节** | `[0]` = `overall_battery_percent`（uint8） |
| `is_split = 1`（分体） | **2 字节** | `[0]` = `left_battery_percent`，`[1]` = `right_battery_percent`（各 uint8） |

#### §14.4.2 电量取值（uint8 编码）

| 值范围 | 含义 |
|------|------|
| `0..100` | 正常百分比 |
| `101..254` | 保留 |
| `255` | sentinel：读取失败 / 临时不可用（例如 I²C 短暂失联） |

#### §14.4.3 生产者不变量（固件 必须 保证）

- **P-B1**：载荷长度与 `is_split` 严格一致（不发 0 字节、不发 3 字节以上）。
- **P-B2**：固件 **透传原始读数**；必须 不在固件层做滑动平均 / 平滑，以防把"读取瞬时失败"洗成"正常低电"。
- **P-B3**：若固件整体无法上报电量 → 整个 Battery 特征 必须 不实现（GATT 发现时不出现）。

#### §14.4.4 消费者规则（主机 必须 保证）

- **C-B1**：若 `capability_bits.is_split = 0` 而载荷 ≠ 1 字节 → 丢弃并记 `battery.length_mismatch`。
- **C-B2**：若 `is_split = 1` 而载荷 ≠ 2 字节 → 丢弃并记 `battery.length_mismatch`。
- **C-B3**：字节值 ∈ [0, 100] → 显示百分比；= 255 → 显示 "读取失败"；101–254 → 显示 "读取失败" 并记 `battery.out_of_range`。
- **C-B4**：主机 可 对渲染值做 ≤ 3 秒的滑动平均作为抖动平滑，必须 不影响 SC-003 判定（即诊断日志中保留原始字节）。

#### §14.4.5 Notify 节流（生产者 必须 保证）

数值性字段节流规则，**或** 关系触发：

- 条件 A：相对上一次已发送的字节值变化 ≥ 1（即 ≥ 1 个百分点）。
- 条件 B：距上一次该字段 notify 已 ≥ 1 秒。

**A ∨ B** 成立 → notify。继承 KBP 1.0 §5 的 "snapshot 未变不发" 规则（即原始字节完全相等时不触发）。

### §14.5 发现与订阅（消费者流程）

- 服务发现仍按 KBP 1.0 §2：通过 `retrieveConnectedPeripherals(withServices: [HID, KBPService])` 枚举已连接外设，GATT 中确认 `AA440AA0-…` 服务存在。
- 服务存在后，消费者 必须 请求发现 service 下 **所有** characteristics，根据各 UUID 的 **存在性** 判定键盘声称支持的 KBP MINOR：
  - 只找到 `AA440AA1-…` → 1.0 only；消费者 必须 不展示 1.1 UI。
  - 找到 `AA440AA1-…` 和 `AA440AA2-…` → 支持 1.1 Connectivity 字段；再按 `AA440AA3-…` 是否存在决定电量 UI。
  - 找到 `AA2` 但 `AA1` 缺失 → 异常；主机 必须 记 `discovery.anomaly` 并按 1.0-only 行为处理（永不裸信任 1.1 字段）。
- 消费者 必须 对已订阅的每个新特征在重连时 **重新** READ + CCC subscribe。

### §14.6 版本信号与升级路径

- 服务 UUID 不变意味着 KBP 1.0 / 1.1 **wire 可识别性等价**；MINOR 判定靠 characteristic 存在性。
- 未来 KBP 1.2+ 必须 继续按本契约的 "**追加 characteristic** 或 **在 Connectivity 的保留尾部字节中追加**" 策略推进（README §9 MINOR 规则）。
- 任何涉及重新解释 byte 位置 / 修改 UUID 的变更一律 **MAJOR**，必须 走 service UUID 替换路径。

### §14.7 与 §10 一致性清单的扩展

本节对应的新增一致性条目（在 `conformance/checklist.md` 落实为 C7–C12；见 `conformance/CONFORMANCE.md`）：

- **C7**：`AA440AA2-…` 若存在：properties = `READ`+`NOTIFY`，带 CCC。
- **C8**：Connectivity READ 返回 ≥ 7 字节，各字段符合 §14.3 与不变量 P-C1..P-C5。
- **C9**：`AA440AA3-…` 若存在：properties = `READ`+`NOTIFY`，带 CCC，且载荷长度与 `is_split` 一致。
- **C10**：状态性字段变化触发 NOTIFY；snapshot 未变抑制继续生效。
- **C11**：数值性字段节流符合 §14.4.5（≥ 1 pp **或** ≥ 1 s，或 关系）。
- **C12**：1.1 新特征仅在分体键盘的 central 角色实现（§8.4 "feature 仅从 central 暴露" 规则延伸到 1.1）。

### §14.8 固件参考映射（非规范性，ZMK）

| KBP 1.1 字段 | ZMK 参考源 |
|-------------|-----------|
| `is_split` 位 | `IS_ENABLED(CONFIG_ZMK_SPLIT) && IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)` |
| `host_state.connected` | `zmk_ble_active_profile_is_connected()` + 订阅 `zmk_ble_active_profile_changed` |
| `profile_index` + `profile_open` + `profile_max_slots` | `zmk_ble_active_profile_index()`、`zmk_ble_active_profile_is_open()`、`ZMK_BLE_PROFILE_COUNT` |
| `split_link_flags` | 订阅 `zmk_split_bt_peripheral_status_changed`；读 `zmk_split_bt_peripherals_connected()` |
| `output_endpoint` | 订阅 `zmk_endpoint_changed`；读 `zmk_endpoints_selected()`（映射 USB_HID → 1，BLE → 2） |
| `charging_flags.bit 0`（`has_left_charging`） | 可选：板级 charger GPIO（整板时为 overall；多数板不实现） |
| `charging_flags.bit 1`（`has_right_charging`） | 可选：peripheral 侧 charger GPIO 经分体同步总线上报（仅 split central 需要） |
| `overall_battery` / `left_battery` / `right_battery` | 订阅 `zmk_battery_state_changed` + `zmk_peripheral_battery_state_changed`；central 侧聚合 |

API 名随 ZMK 版本可能有变；实施阶段（`zmk-keybeacon` 外部模块）必须 核对当前 ZMK main 分支的实际符号。
