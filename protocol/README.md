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
