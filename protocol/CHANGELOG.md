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
