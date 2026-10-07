# KeyBeacon Protocol — Changelog

All notable changes to the **KeyBeacon Protocol (KBP)** are recorded here. KBP uses semantic
versioning; the **service UUID is the MAJOR-version signal** (see `README.md` §9). Each released
version corresponds to an immutable `protocol-vX.Y.Z` git tag in this repository, which downstream
implementers (apps, firmware pins) resolve against.

The format follows [Keep a Changelog](https://keepachangelog.com/) loosely and
[Semantic Versioning](https://semver.org/).

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
