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

- **1.0.0** — Initial KeyBeacon Protocol: BLE GATT service/characteristic, service-UUID
  identification, GAP-name identity, `[layer_index][mods][layer_name]` payload, READ/NOTIFY with
  change suppression, conformance checklist, and UUID-based MAJOR versioning. Consolidates the
  feature-001 status-snapshot contract and the feature-002 discovery-and-identity amendment.

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

- **1.0.0** — 初始 KeyBeacon 协议：BLE GATT 服务/特征、基于服务 UUID 的身份识别、GAP 名称
  身份、`[layer_index][mods][layer_name]` 载荷、带变化抑制的 READ/NOTIFY、一致性检查清单，以及
  基于 UUID 的 MAJOR 版本控制。整合了 feature-001 状态快照合约与 feature-002 发现与身份修正。
