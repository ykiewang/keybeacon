# Phase 1 — Data Model: zmk-keybeacon module KBP 1.1

**Feature**: 002-zmk-keybeacon-kbp11

**Date**: 2026-10-09

Scope: entities **inside the firmware module**. The wire-level entities (what bytes flow over BLE) are specified by the protocol doc and summarized in `contracts/connectivity-characteristic.md` and `contracts/battery-characteristic.md`. This document covers how the module **stores and transitions** those bytes.

Terminology: "payload" = the byte sequence sent on a NOTIFY; "cache" = the module's last-sent payload for change-suppression; "snapshot" = the live payload built from current state before comparison.

---

## E1. Connectivity payload entity (`conn_payload_t`)

**Purpose**: holds the 7 bytes defined in `protocol/README.md §14.3.1`. Rebuilt from scratch on every subscribed event.

**Fields**:

| Field | Byte | Size | Source |
|-------|------|------|--------|
| `capability_bits` | `[0]` | 1 | compile-time constant `keybeacon_cap_bits` (see research.md §R3) |
| `host_state` | `[1]` | 1 | bit 0 = `zmk_ble_active_profile_is_connected()`; bits 1–2 = 0 (unknown reason); bits 3–7 = 0 |
| `profile_index` | `[2]` | 1 | bits 0–6 = `zmk_ble_active_profile_index() + 1` (converted to 1-based); bit 7 = `zmk_ble_active_profile_is_open()` |
| `profile_max_slots` | `[3]` | 1 | `ZMK_BLE_PROFILE_COUNT` (compile-time) |
| `split_link_flags` | `[4]` | 1 | bit 0 = central-only `1` under `CONFIG_ZMK_SPLIT_BLE`; bit 1 = `right_online` (derived from `peripheral_battery_last_seen_ms` + 10 s TTL, see E2); bits 2–7 = 0 |
| `output_endpoint` | `[5]` | 1 | map `zmk_endpoints_selected().transport` → 1 (USB) / 2 (BLE) / 0 (unresolved) |
| `charging_flags` | `[6]` | 1 | 0 in v1.1.0 (no charger GPIO support) |

**Invariants**:

- `sizeof(conn_payload_t) == 7` enforced by `BUILD_ASSERT`.
- All P-C1..P-C5 from §14.3.3 hold by construction (capability bits are compile-time constants that already satisfy the dependencies).

**State transitions**:

```text
             ┌────────────── wait ──────────────┐
             │                                  │
   [BOOT]────┼─> cache = build_snapshot()       │
             │       │                          │
             │       └── compare: trivially =   │
             │           (no NOTIFY on init)    │
             └──────────────────────────────────┘
                   │
          event received  (profile / endpoint / peripheral_battery)
                   │
                   ▼
      snap = build_snapshot()
          │
      snap == cache ? ──── yes ──> suppress (constitutional rule §C3 extended)
          │ no
          ▼
      bt_gatt_notify(AA2, snap, 7)
      cache = snap
```

**Lifetime**: static RAM (14 bytes total: cache + current scratch); allocated in BSS of `keybeacon.c`, no dynamic allocation.

---

## E2. Peripheral battery tracking entity (`peripheral_battery_slot_t`)

**Purpose**: per-slot last-seen battery percent and timestamp, used by both E1's `right_online` bit and E3's right-byte emission.

**Fields** (one entry per `CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS`, bounded by 1 for 1-peripheral splits like corne):

| Field | Type | Semantics |
|-------|------|-----------|
| `last_percent` | `uint8_t` | 0..100 valid or 255 sentinel (initial 255) |
| `last_seen_ms` | `int64_t` | `k_uptime_get()` at the last `zmk_peripheral_battery_state_changed` event for this slot; 0 at boot |

**State transitions**:

```text
On ZMK event (source, state_of_charge):
    slot = &peripheral_slots[source]
    slot->last_percent = state_of_charge
    slot->last_seen_ms = k_uptime_get()
    // trigger payload rebuild + change-check in both E1 and E3

On 1 Hz timer tick:
    for each slot:
        if last_seen_ms > 0 && (now_ms - slot->last_seen_ms) > 10_000:
            // slot is considered offline; cap bit may need no change
            // but E1's build_snapshot() reads this inline each time
            // E3's build_snapshot() emits last_percent regardless (host
            // decides staleness per 001-connectivity-power FR-015 3s rule)
```

**Lifetime**: static array `peripheral_slots[CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS]`; sized at compile time; zero on integer boards. Total RAM: 1 peripheral × 9 bytes = 9 B for corne.

---

## E3. Battery payload entity (`batt_payload_t`)

**Purpose**: holds the 1-or-2-byte payload defined in `protocol/README.md §14.4.1`.

**Fields**:

| Field | Byte | Condition | Source |
|-------|------|-----------|--------|
| `overall_percent` | `[0]` | `IS_ENABLED(CONFIG_ZMK_SPLIT)` is `false` | last cached `zmk_battery_state_changed` event value; 255 before first event |
| `left_percent` | `[0]` | `IS_ENABLED(CONFIG_ZMK_SPLIT)` is `true` | same as `overall_percent` above (central = left half by convention) |
| `right_percent` | `[1]` | `IS_ENABLED(CONFIG_ZMK_SPLIT)` is `true` | `peripheral_slots[0].last_percent`; 255 if slot has never been seen |

**Invariants**:

- Payload length is **exactly 1 byte** when `!IS_ENABLED(CONFIG_ZMK_SPLIT)`, **exactly 2 bytes** when `IS_ENABLED(CONFIG_ZMK_SPLIT)`. Enforced by two mutually-exclusive `BUILD_ASSERT`s.
- Each byte is `0..100` or `255`; never `101..254`. Enforced at write time via a `MIN(100, value)` clamp on normal readings and explicit `255` on sentinel.

**State transitions**:

```text
Event path (zmk_battery_state_changed or zmk_peripheral_battery_state_changed):
    update E2 cache (if peripheral) or local overall cache (if central)
    build_snapshot(E3)
    if snapshot != E3.cache:
        bt_gatt_notify(AA3, snapshot, N)
        E3.cache = snapshot
        E3.last_emit_ms = k_uptime_get()

1 Hz timer path:
    build_snapshot(E3)
    if snapshot != E3.cache:
        bt_gatt_notify(...)  # covers the ≥1 s floor of §14.4.5
        E3.cache = snapshot
        E3.last_emit_ms = k_uptime_get()
    # snapshot == cache: nothing to do, snapshot-unchanged suppression
```

**Lifetime**: static RAM; 1 or 2 bytes cache + 1 or 2 bytes scratch + 8 bytes timestamp = ≤ 12 B.

---

## E4. Capability declaration entity (compile-time)

**Purpose**: declarative, compile-time const value baked into `keybeacon_cap_bits` + the Kconfig-reading macros that gate each sub-feature. Not an "entity" in a runtime sense — captured here so the data-model is complete.

**Fields** (all compile-time `uint8_t` masks, OR'd into `keybeacon_cap_bits`):

| Mask | Name | Expression | v1.1.0 value on corne |
|------|------|------------|-----------------------|
| `0x01` | `is_split` | `IS_ENABLED(CONFIG_ZMK_SPLIT)` | 1 |
| `0x02` | `has_host_connection` | always `1` (API always available on central) | 1 |
| `0x04` | `has_profile` | always `1` (API always available on central) | 1 |
| `0x08` | `has_split_link` | `IS_ENABLED(CONFIG_ZMK_SPLIT) && IS_ENABLED(CONFIG_ZMK_SPLIT_BLE)` | 1 |
| `0x10` | `has_output_endpoint` | always `1` (endpoints API always available) | 1 |
| `0x20` | `has_left_charging` | always `0` in v1.1.0 (no charger GPIO) | 0 |
| `0x40` | `has_right_charging` | always `0` in v1.1.0 | 0 |
| `0x80` | reserved | MUST be 0 | 0 |

**Invariant**: P-C1 (`has_split_link ⇒ is_split`) and P-C5 (`has_right_charging ⇒ is_split ∧ has_left_charging`) are satisfied **by construction**: `has_right_charging = 0` kills the P-C5 implication's antecedent; `has_split_link` is only set when `is_split` is also set.

**On corne (central-build, CONFIG_ZMK_SPLIT=y, CONFIG_ZMK_SPLIT_BLE=y)**:

```text
keybeacon_cap_bits = 0x01 | 0x02 | 0x04 | 0x08 | 0x10
                   = 0x1F
```

Byte 0 of every Connectivity payload is `0x1F` on the user's corne build.

**On an integer-board build (CONFIG_ZMK_SPLIT=n)**:

```text
keybeacon_cap_bits = 0x00 | 0x02 | 0x04 | 0x00 | 0x10
                   = 0x16
```

Host sees `is_split = 0`, `has_split_link = 0` — split UI is hidden entirely.

---

## E5. Service entity (`keybeacon_svc`)

**Purpose**: the Zephyr `BT_GATT_SERVICE_DEFINE` block that registers service `AA440AA0-…` with its three characteristics.

**Fields**:

- **Primary service** declaration (unchanged).
- **Characteristic 1**: `AA440AA1-…` (KBP 1.0, unchanged byte-for-byte from v1.0.0; see `keybeacon.c` lines 46–51 for the v1.0.0 pattern).
- **Characteristic 2**: `AA440AA2-…` (new; `READ|NOTIFY` + CCC) — gated by `#if IS_ENABLED(CONFIG_ZMK_KEYBEACON_CONNECTIVITY)`.
- **Characteristic 3**: `AA440AA3-…` (new; `READ|NOTIFY` + CCC) — gated by `#if IS_ENABLED(CONFIG_ZMK_KEYBEACON_BATTERY)`.

**Invariants**:

- The service UUID line and the AA1 characteristic + CCC block are **not modified**. FR-G1 verifiable via `git diff zmk-keybeacon.c v1.0.0..feat/kbp-1.1-connectivity-power -- :/<BT_GATT_PRIMARY_SERVICE line>:/<AA1 CCC line>` showing those lines unchanged.
- The AA2 and AA3 attributes **must** reside inside the same `BT_GATT_SERVICE_DEFINE` block (not a separate service) so they share the primary-service UUID — per protocol §14.2 "the producer MUST NOT introduce a new service for 1.1".

**Attribute indices for `bt_gatt_notify()`**:

- `keybeacon_svc.attrs[1]` → AA1 characteristic value (unchanged — the v1.0.0 code calls `bt_gatt_notify(NULL, &keybeacon_svc.attrs[1], ...)` and this feature preserves that index).
- `keybeacon_svc.attrs[4]` → AA2 characteristic value (new; index derived from fixed Zephyr GATT macro expansion: primary(0) + chrc_decl(1) + chrc_value(2) + ccc(3) = 4 for the next chrc_value… but the exact index depends on whether CCC is placed differently; see implementation note).

**Implementation note**: Zephyr's `BT_GATT_CHARACTERISTIC(uuid, props, perm, read_cb, write_cb, user_data)` macro expands to 2 attributes (declaration + value); `BT_GATT_CCC(...)` expands to 1 attribute. So the attribute layout is:

| Index | Attribute |
|-------|-----------|
| 0 | Primary service decl |
| 1 | AA1 chrc decl |
| 2 | AA1 chrc value |
| 3 | AA1 CCC |
| 4 | AA2 chrc decl |
| 5 | AA2 chrc value |
| 6 | AA2 CCC |
| 7 | AA3 chrc decl |
| 8 | AA3 chrc value |
| 9 | AA3 CCC |

Wait — the v1.0.0 code uses `&keybeacon_svc.attrs[1]` for `bt_gatt_notify`, which corresponds to the chrc **declaration**, not the value. Checking Zephyr semantics: `bt_gatt_notify(conn, attr, data, len)` takes a pointer to either the chrc declaration OR the chrc value; both work (Zephyr walks forward to find the value). To preserve the exact v1.0.0 byte-for-byte call, the module keeps `&keybeacon_svc.attrs[1]` for AA1 and uses `&keybeacon_svc.attrs[4]` + `&keybeacon_svc.attrs[7]` (both chrc declarations) for AA2 + AA3. **These exact offsets are brittle to future characteristic additions; keep them in named constants `#define KBP_ATTR_AA2 4` / `#define KBP_ATTR_AA3 7`.**

---

## Entity dependency graph

```text
┌──────────────────────┐         ┌────────────────────────┐
│  Compile-time        │         │  Service entity (E5)   │
│  Kconfig symbols     │────────▶│  BT_GATT_SERVICE_DEFINE│
│  (CONFIG_ZMK_...)    │         │  with 3 characteristics│
└──────────┬───────────┘         └─────────┬──────────────┘
           │                               │
           ▼                               ▼
┌──────────────────────┐         ┌────────────────────────┐
│  Capability          │         │  Zephyr GATT runtime   │
│  declaration (E4)    │         │  CCC + bt_gatt_notify  │
│  = keybeacon_cap_bits│         └─────────┬──────────────┘
└──────────┬───────────┘                   │
           │                               │
           ▼                               ▼
┌──────────────────────┐         ┌────────────────────────┐
│  ZMK event handlers  │────────▶│  Payload entities      │
│  (profile/endpoint/  │         │  E1 Connectivity (7B)  │
│  peripheral_batt)    │         │  E3 Battery (1 or 2 B) │
└──────────┬───────────┘         └─────────┬──────────────┘
           │                               │
           │     ┌─────────────────────────┤
           │     │                         │
           ▼     ▼                         ▼
┌──────────────────────┐         ┌────────────────────────┐
│  E2 Peripheral       │         │  1 Hz k_work_delayable │
│  battery slot cache  │────────▶│  (OR-relation ≥1 s     │
│  (last_percent +     │         │   floor for E3)        │
│   last_seen_ms)      │         └────────────────────────┘
└──────────────────────┘
```

**Reading guide**: everything compile-time flows down from Kconfig → cap bits → service shape. Runtime data flows: ZMK events update E2 (and local overall cache for the central) → trigger E1 and E3 snapshot rebuilds → change-detect against cache → NOTIFY on diff. The 1 Hz worker only drives E3 (the Battery characteristic), covering §14.4.5's "≥ 1 s since last emit" floor.
