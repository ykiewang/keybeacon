# KeyBeacon Protocol — Changelog

All notable changes to the **KeyBeacon Protocol (KBP)** are recorded here. KBP uses semantic
versioning; the **service UUID is the MAJOR-version signal** (see `README.md` §9). Each released
version corresponds to an immutable `protocol-vX.Y.Z` git tag in this repository, which downstream
implementers (apps, firmware pins) resolve against.

The format follows [Keep a Changelog](https://keepachangelog.com/) loosely and
[Semantic Versioning](https://semver.org/).

## 1.1.0

**Released as tag `protocol-v1.1.0`.** MINOR amendment to KBP 1.x; the KBP 1.0
wire contract is **unchanged**.

### Added

- **Two new optional characteristics** under the same primary service
  `AA440AA0-F5ED-4C48-84A1-8062D20D3D55`:
  - **Connectivity characteristic** `AA440AA2-F5ED-4C48-84A1-8062D20D3D55`
    (`READ`+`NOTIFY`, with CCC). Carries all state-ish fields in a fixed
    **≥ 7-byte little-endian** payload:
    - `[0]` `capability_bits` (uint8): per-field capability declaration;
      bit 0 = `is_split`, bit 1 = `has_host_connection`, bit 2 = `has_profile`,
      bit 3 = `has_split_link` (requires bit 0), bit 4 = `has_output_endpoint`,
      bit 5 = `has_left_charging` (overall when `is_split = 0`),
      bit 6 = `has_right_charging` (requires `is_split = 1`), bit 7 reserved.
    - `[1]` `host_state` (connected + last_disconnect_reason).
    - `[2..3]` `profile_index` + `profile_open` + `profile_max_slots`.
    - `[4]` `split_link_flags` (left_online + right_online).
    - `[5]` `output_endpoint` (0 unknown / 1 USB / 2 BLE / 3–255 reserved).
    - `[6]` `charging_flags` (bit 0 left/overall, bit 1 right).
    - `[7..]` reserved trailing bytes (consumer MUST ignore for MINOR
      forward-compatibility).
  - **Battery characteristic** `AA440AA3-F5ED-4C48-84A1-8062D20D3D55`
    (`READ`+`NOTIFY`, with CCC). Length varies with `is_split`: 1 byte
    overall when `is_split = 0`, or 2 bytes `[left_percent, right_percent]`
    when `is_split = 1`. Each byte: `0..100` = percent, `255` = sentinel
    (read failed / temporarily unavailable), `101..254` = reserved.
- **Capability bits** declared per-field so a host can enumerate exactly
  which 1.1 fields a given firmware supports (field-level honest
  degradation; aligns with the "Observable Degradation Over Guessing"
  governance principle).
- **`is_split` bit** at `capability_bits.bit 0`, so hosts no longer need
  to infer split-ness from BAS instance count or field presence.
- **Per-half charging flags** (bit 5 / bit 6 split) so split keyboards
  with asymmetric charger hardware (e.g., left half only) declare each
  side independently; hosts render per side.
- **Staleness consumption rule** for hosts (recorded in
  `specs/001-connectivity-power/spec.md` FR-015 and the data-model's
  `StalenessTracker`): 3-second no-notify threshold → field rendered as
  "last known value + timestamp" with 50% opacity; BLE disconnect →
  all fields immediately stale.
- **Notify-throttling rule for numeric fields**: battery updates emit
  on **≥ 1 pp change OR ≥ 1 s since last emit** (OR relation), so
  typing-heavy sessions do not swamp the ATT with sub-pp jitter.
- **Checklist items C7–C12** in the conformance kit, covering `AA2`/`AA3`
  presence and properties, Connectivity payload shape, NOTIFY behavior,
  numeric throttling, and the split-central-only rule.

### Changed

- **README** adds §13 Changelog entry for 1.1.0 and the full §14 KBP 1.1
  normative section (English + Chinese side-by-side, per the Bilingual
  Normative Docs governance principle).
- **No wire change** to KBP 1.0: service UUID `AA440AA0-…` and the
  `AA440AA1-…` payload remain **byte-identical** to 1.0.0.

### Deprecated

- Nothing.

### Migration

| Combination | Result |
|-------------|--------|
| KBP 1.0 firmware + KBP 1.1 host | Host finds only `AA440AA1-…` on GATT discovery; the entire 1.1 UI (connectivity / battery card) is hidden; layer / modifier display works bit-for-bit identical to 1.0. |
| KBP 1.1 firmware + KBP 1.0 host | Host subscribes to `AA440AA1-…` only; firmware emits no NOTIFY on `AA440AA2-…` / `AA440AA3-…` (CCC not enabled); 1.0 behavior preserved. |
| KBP 1.1 firmware + KBP 1.1 host, partial field support | Host enumerates `capability_bits`; fields with bit = 0 are **completely hidden** (not greyed, not "N/A", not "0%"); fields with bit = 1 are rendered live. |
| KBP 1.1 split firmware with asymmetric charger (left only) | `has_left_charging = 1`, `has_right_charging = 0`; UI renders the charge icon on the left half, nothing on the right. |

See `specs/001-connectivity-power/research.md` §11 for the full
compatibility matrix.

## 1.0.0

**Released as tag `protocol-v1.0.0`.**

Initial published KeyBeacon Protocol. Consolidates two previously-internal contracts into one
standalone, independently-versioned standard:

- **Transport & payload** (from the feature-001 status-snapshot contract): one custom BLE GATT
  primary service `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` with a `READ`+`NOTIFY` status
  characteristic `AA440AA1-…` (CCC present), carrying a variable-length little-endian
  `[layer_index][mods][layer_name]` snapshot (≥ 2 bytes; `layer_name` UTF-8, no trailing NUL).
- **Change-suppressed NOTIFY**: notifications fire only when the snapshot changes; an idle
  keyboard produces zero traffic.
- **Discovery & identity** (from the feature-002 discovery-and-identity amendment): identity is
  the **service UUID** (never name/model); connected HID keyboards stop advertising, so hosts
  enumerate already-connected peripherals and confirm the service via GATT; the human-readable
  display name is the **BLE GAP device name**, with a generic fallback when absent.
- **Versioning rule**: MAJOR ⇒ new service UUID; MINOR ⇒ appended reserved trailing bytes or an
  optional characteristic (same UUID); PATCH ⇒ clarifications only.
- **Conformance checklist** (§10) defining what "a keyboard supports KBP 1.x" means.

No wire change versus the as-shipped feature-001/002 behavior — this release packages and governs
the existing contract; it does not alter bytes on the air.

---

<a id="zh-changelog"></a>

# KeyBeacon 协议 — 变更日志(中文版)

**English** · [中文](#zh-changelog)

**KeyBeacon 协议(KBP)** 的所有重要变更都记录于此。KBP 采用语义化版本;**服务 UUID 即为 MAJOR
版本信号**(见 `README.md` §9)。每个已发布版本对应本仓库中一个不可变的 `protocol-vX.Y.Z` git
标签,下游实现者(应用、固件 pin)据此解析。

格式大致遵循 [Keep a Changelog](https://keepachangelog.com/) 与
[语义化版本](https://semver.org/)。

## 1.1.0

**以标签 `protocol-v1.1.0` 发布。** KBP 1.x 的 MINOR 修订；KBP 1.0 的线上
合约**不变**。

### 新增

- 在同一主服务 `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` 下 **新增两个可选特征**：
  - **Connectivity 特征** `AA440AA2-F5ED-4C48-84A1-8062D20D3D55`
    （`READ`+`NOTIFY`，带 CCC）。承载所有状态性字段，固定 **≥ 7 字节、小端序** 载荷：
    - `[0]` `capability_bits`（uint8）：按字段的能力声明；
      bit 0 = `is_split`，bit 1 = `has_host_connection`，bit 2 = `has_profile`，
      bit 3 = `has_split_link`（要求 bit 0），bit 4 = `has_output_endpoint`，
      bit 5 = `has_left_charging`（`is_split = 0` 时为 overall），
      bit 6 = `has_right_charging`（要求 `is_split = 1`），bit 7 保留。
    - `[1]` `host_state`（connected + last_disconnect_reason）。
    - `[2..3]` `profile_index` + `profile_open` + `profile_max_slots`。
    - `[4]` `split_link_flags`（left_online + right_online）。
    - `[5]` `output_endpoint`（0 未知 / 1 USB / 2 BLE / 3–255 保留）。
    - `[6]` `charging_flags`（bit 0 左/整板，bit 1 右）。
    - `[7..]` 保留尾部字节（消费者 必须 忽略，以保证 MINOR 向上兼容）。
  - **Battery 特征** `AA440AA3-F5ED-4C48-84A1-8062D20D3D55`
    （`READ`+`NOTIFY`，带 CCC）。长度随 `is_split`：`is_split = 0` 时 1 字节 overall，
    `is_split = 1` 时 2 字节 `[left_percent, right_percent]`。每字节：
    `0..100` = 百分比，`255` = sentinel（读取失败 / 临时不可用），
    `101..254` = 保留。
- **能力位**按字段声明，让主机可枚举固件实际支持了哪些 1.1 字段
  （字段级诚实降级；对齐治理原则"Observable Degradation Over Guessing"）。
- **`is_split` 位**位于 `capability_bits.bit 0`，主机不再需要从 BAS 实例数或
  字段存在性反推分体性。
- **按半充电位**（bit 5 / bit 6 分开）支持分体键盘左右半硬件不对称
  （例如只有左半有 charger GPIO）时按侧独立声明；主机按侧渲染。
- 主机侧 **陈旧消费规则**（载于 `specs/001-connectivity-power/spec.md` FR-015 与
  data-model 的 `StalenessTracker`）：单字段 3 秒无 notify → 渲染为"最后已知值 +
  时间戳"（50% 透明度）；BLE 断连 → 所有字段立即陈旧。
- **数值性字段节流规则**：电量变化满足 **≥ 1 pp 或距上次 notify ≥ 1 s**
  （或 关系）才 notify，使重度打字时不被亚百分点抖动淹没 ATT。
- 一致性套件新增 **C7–C12** 条目，覆盖 `AA2` / `AA3` 存在性与属性、Connectivity
  载荷结构、NOTIFY 行为、数值节流以及分体 central 唯一规则。

### 变更

- **README** 新增 §13 Changelog 1.1.0 条目与完整的 §14 KBP 1.1 规范章节
  （英中双语并排，对齐治理原则"Bilingual Normative Docs"）。
- KBP 1.0 **无线上变更**：服务 UUID `AA440AA0-…` 与 `AA440AA1-…` 载荷与 1.0.0
  **字节一致**。

### 弃用

- 无。

### 迁移

| 组合 | 结果 |
|------|------|
| KBP 1.0 固件 + KBP 1.1 主机 | GATT 发现时主机只找到 `AA440AA1-…`；整张 1.1 UI（连接 / 电量卡片）整张隐藏；层 / 修饰键显示与 1.0 字节一致。 |
| KBP 1.1 固件 + KBP 1.0 主机 | 主机只订阅 `AA440AA1-…`；固件在 `AA440AA2-…` / `AA440AA3-…` 上不发 NOTIFY（CCC 未启用）；1.0 行为完整保留。 |
| KBP 1.1 固件 + KBP 1.1 主机，字段部分支持 | 主机枚举 `capability_bits`；bit = 0 的字段 **整个隐藏**（不灰显、不 "N/A"、不 "0%"）；bit = 1 的字段实时渲染。 |
| KBP 1.1 分体固件 + 不对称充电硬件（仅左半） | `has_left_charging = 1`，`has_right_charging = 0`；UI 在左半渲染充电图标，右半完全不出现。 |

完整兼容矩阵详见 `specs/001-connectivity-power/research.md` §11。

## 1.0.0

**以标签 `protocol-v1.0.0` 发布。**

首个发布的 KeyBeacon 协议。将两份此前内部的合约整合为一个独立、独立版本化的标准:

- **传输与载荷**(来自 feature-001 状态快照合约):一个自定义 BLE GATT 主服务
  `AA440AA0-F5ED-4C48-84A1-8062D20D3D55`,带一个 `READ`+`NOTIFY` 状态特征 `AA440AA1-…`(存在
  CCC),承载可变长度、小端序的 `[layer_index][mods][layer_name]` 快照(≥ 2 字节;`layer_name`
  为 UTF-8,无尾部 NUL)。
- **变化抑制的 NOTIFY**:仅在快照变化时发送通知;空闲键盘产生零流量。
- **发现与身份**(来自 feature-002 发现与身份修正):身份即**服务 UUID**(绝不用名称/型号);已连接
  的 HID 键盘停止广播,因此主机枚举已连接外设并通过 GATT 确认服务;人类可读的显示名称是 **BLE GAP
  设备名称**,缺失时使用通用占位名。
- **版本规则**:MAJOR ⇒ 新服务 UUID;MINOR ⇒ 追加保留尾部字节或可选特征(同 UUID);PATCH ⇒ 仅澄清。
- **一致性检查清单**(§10)定义了"键盘支持 KBP 1.x"的含义。

相较已交付的 feature-001/002 行为无线上变更 —— 本次发布打包并治理既有合约,不改变空中字节。
