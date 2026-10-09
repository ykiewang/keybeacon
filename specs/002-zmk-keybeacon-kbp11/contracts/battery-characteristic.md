# Contract: Battery characteristic (`AA440AA3-F5ED-4C48-84A1-8062D20D3D55`)

**Feature**: 002-zmk-keybeacon-kbp11

**Normative source**: `protocol/README.md §14.4` (keybeacon main repo).

## 1. GATT shape

| Item | Value |
|------|-------|
| Service UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` (shared) |
| Characteristic UUID | `AA440AA3-F5ED-4C48-84A1-8062D20D3D55` |
| Properties | `BT_GATT_CHRC_READ \| BT_GATT_CHRC_NOTIFY` |
| Permission | `BT_GATT_PERM_READ` |
| Descriptor | `BT_GATT_CCC(cb, BT_GATT_PERM_READ \| BT_GATT_PERM_WRITE)` |
| Presence | **optional**; registered iff `CONFIG_ZMK_KEYBEACON_BATTERY=y` AND `CONFIG_ZMK_KEYBEACON=y` AND `CONFIG_ZMK_SPLIT_ROLE_CENTRAL=y` (or non-split) AND `CONFIG_ZMK_BLE=y` |

## 2. Payload layout (length depends on `is_split`)

| Case | Length | Bytes |
|------|--------|-------|
| `CONFIG_ZMK_SPLIT=n` (integer board) | **1 byte** | `[0] = overall_percent` |
| `CONFIG_ZMK_SPLIT=y` (split) | **2 bytes** | `[0] = left_percent`, `[1] = right_percent` |

Each byte encoding:

| Value | Meaning |
|-------|---------|
| `0..100` | normal percent |
| `101..254` | reserved — producer MUST NOT emit |
| `255` | sentinel: read failed / temporarily unavailable (fresh boot before first event; sync-bus loss; API returns -EINVAL) |

**BUILD_ASSERT**:

```c
#if IS_ENABLED(CONFIG_ZMK_SPLIT)
BUILD_ASSERT(KBP_BATT_PAYLOAD_LEN == 2, "KBP 1.1 §14.4.1: split battery payload must be 2 bytes");
#else
BUILD_ASSERT(KBP_BATT_PAYLOAD_LEN == 1, "KBP 1.1 §14.4.1: integer-board battery payload must be 1 byte");
#endif
```

## 3. Invariants (producer-side; firmware MUST)

- **P-B1**: payload length matches `is_split` exactly. Enforced by `BUILD_ASSERT` (see §2).
- **P-B2**: raw ADC readings pass through — firmware MUST NOT smooth / average / debounce at the firmware layer. Each `zmk_battery_state_changed` event's `state_of_charge` goes directly into the cache; same for `zmk_peripheral_battery_state_changed`.
- **P-B3**: if firmware cannot report battery at all → characteristic MUST NOT be registered. Satisfied by `CONFIG_ZMK_KEYBEACON_BATTERY` gating (keyboard author opts out at build time).
- **P-B4**: byte values `101..254` MUST NOT be emitted. Enforced by `MIN(100, value)` clamp on event-driven path (ZMK events deliver uint8 up to 255 but 255 is only the sentinel, which the module writes explicitly).

## 4. NOTIFY throttling (§14.4.5)

The OR relation: emit when **A** OR **B**:

- **A**: any byte value in the rebuilt snapshot differs from the cached last-sent payload by ≥ 1 (equivalent to byte-value delta ≥ 1 pp since percent and byte are 1:1 on `0..100`).
- **B**: ≥ 1 second has elapsed since the last emit of this characteristic.

Combined with the KBP 1.0 §5 "snapshot-unchanged suppression" rule (byte-for-byte identical snapshot ⇒ no NOTIFY), the effective policy is:

```text
on event or 1Hz tick:
    snap = rebuild_payload()
    if snap == cache:  # suppression
        return
    now = k_uptime_get()
    if event path:
        emit  # condition A
    elif now - last_emit_ms >= 1000:
        emit  # condition B
    else:
        # change detected but < 1 s since last emit; wait for next 1 Hz tick
        return
```

**Observation**: in practice SC-003 ("≤ 60 NOTIFY in 60 s") holds because:
- Steady-state typing with no real battery change: cache == snap, suppression wins.
- 1 pp drift events are naturally ≥ 1 s apart (battery ADC jitter at 10 Hz would be the bound).
- Worst case burst: user plugs charger during observation window → 1 pp per few seconds, well under the 60 cap.

## 5. READ policy

GATT READ returns the current cached payload (1 or 2 bytes), served via `bt_gatt_attr_read`.

## 6. Degradation hooks

| Scenario | Producer behaviour |
|----------|-------------------|
| `CONFIG_ZMK_KEYBEACON_BATTERY=n` | characteristic NOT registered |
| No `zmk_battery_state_changed` event has fired yet (fresh boot) | `overall_percent` / `left_percent` = `255` |
| `CONFIG_ZMK_SPLIT=y` but peripheral never paired | `right_percent` = `255` indefinitely until first `zmk_peripheral_battery_state_changed` event |
| Peripheral sync-bus temporarily lost | `right_percent` stays at last-known value for up to 10 s (per E2 TTL), then transitions to `255` on next 1 Hz tick |
| Integer board but `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=n` compile error combination | Not a valid combination — `BUILD_ASSERT` reminds the keyboard author to pick one |

## 7. Mapping back to feature spec

| FR / SC | Covered by this contract |
|---------|--------------------------|
| FR-G1 | characteristic UUID + service UUID exact match |
| FR-G2 | section 1 "registered iff" clause |
| FR-B1 | section 2 BUILD_ASSERT |
| FR-B2 | section 2 encoding table + section 3 P-B4 |
| FR-B3 | section 4 OR-relation throttling |
| FR-B4 | section 3 P-B2 |
| FR-B5 | section 6 "fresh boot" and "sync-bus loss" rows |
| FR-B6 | section 1 "registered iff" + section 6 "KEYBEACON_BATTERY=n" |
| SC-001 (conformance tool PASS C9 / C11) | sections 1–4 cover C9 (shape) and C11 (throttling observable) |
| SC-003 (≤ 60 NOTIFY / 60 s continuous typing) | section 4 "Observation" paragraph |
| SC-004 (KBP 1.0 host regression) | section 1 "registered iff" — AA3 is new, doesn't affect AA1 |

## 8. Non-goals in v1.1.0

- No support for N > 1 peripheral slots. The split case assumes exactly 1 peripheral (corne-style). N > 1 extends to a longer payload in a later KBP MINOR.
- No battery-prediction, no low-battery warning emission (host responsibility).
- No encoding of charging state on this characteristic — that's in `charging_flags` of the Connectivity characteristic.
