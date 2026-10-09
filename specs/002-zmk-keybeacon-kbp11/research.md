# Phase 0 — Research: zmk-keybeacon module KBP 1.1

**Feature**: 002-zmk-keybeacon-kbp11

**Date**: 2026-10-09

Purpose: verify the ZMK API hints in `protocol/README.md §14.8` against the **exact commit** this feature targets, resolve "NEEDS CLARIFICATION" items from `plan.md`'s Technical Context, and record the compile-time degradation strategy (FR-K3) with concrete `#if defined`-guards.

**Pinned reference**: `zmkfirmware/zmk @ 6b44d33db2f4bad7d98e475e6f7968493b05af73` (June 16 2025 — "feat(split): Runtime selection of split transport"), as declared in `/Users/wangyuting19/kbd/zmk-config-corne/config/west.yml` L16.

**Method**: local checkout at `/Users/wangyuting19/kbd/zmk/`, `git show 6b44d33d:<header path>` for each §14.8 symbol.

## R1. ZMK API availability at pin — field-by-field

### R1.1 `host_state.connected` + `last_disconnect_reason` → event: `zmk_ble_active_profile_changed`

**Decision**: use `zmk_ble_active_profile_is_connected()` (public, in `<zmk/ble.h>`), subscribe to `zmk_ble_active_profile_changed` from `<zmk/events/ble_active_profile_changed.h>`.

**Rationale**: both symbols present and public at pin. Event struct carries `uint8_t index` + `struct zmk_ble_profile *profile` (no explicit reason code), which means we can detect **connected vs disconnected** but **not the reason**. Firmware will emit `last_disconnect_reason = 0 (unknown)` for every state change — this is permitted per §14.3.1 (`last_disconnect_reason` enum includes `0 = unknown`). An upstream ZMK that adds a reason code can be opted into later via `#if defined(ZMK_BLE_PROFILE_DISCONNECTED_REASON)` sentinel macro.

**Alternatives considered**:
- Peek `bt_conn` disconnect reasons via a Zephyr-level HCI callback: rejected — crosses abstraction, breaks "module is ZMK-only"; also requires a bt_conn_cb registration that would conflict with other modules.
- Only emit `host_state` if we can get the reason: rejected — defeats the whole P1 user story on this pinned commit.

### R1.2 `profile_index` + `profile_open` + `profile_max_slots`

**Decision**: directly call the public API triplet:
- `zmk_ble_active_profile_index()` → returns `int` (0-based). Convert to 1-based for byte 2 bits 0–6 (§14.3.1).
- `zmk_ble_active_profile_is_open()` → returns `bool`. Place in byte 2 bit 7.
- `ZMK_BLE_PROFILE_COUNT` macro → compile-time integer. Place in byte 3 (uint8).

**Rationale**: all three present and public at pin (verified in `app/include/zmk/ble.h` lines 16, 32, 34). `ZMK_BLE_PROFILE_COUNT` is a macro, not a function, so it is compile-time (no runtime cost) and value is `CONFIG_BT_MAX_PAIRED - CONFIG_ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS` on central builds.

**Caveat (encoded in FR-C4)**: ZMK's `profile_index` is **0-based**; the KBP wire protocol §14.3.1 uses **1-based** (0 = not applicable). Module must `+1` the ZMK value. Only `profile_index == 0` would collide with "not applicable" — but ZMK's index 0 is the first profile, so firmware MUST emit `zmk_value + 1` for every call.

### R1.3 `split_link_flags.left_online` + `right_online`

**Decision**: this is the most involved field at this pin. Design:

- **`left_online` (byte 4 bit 0)**: hard-coded `1` when the module compiles into a central image (the central IS the "local half" from its own observation — the firmware wouldn't be running otherwise). This matches ZMK's keyboard concept where the central is always "online" relative to itself.
- **`right_online` (byte 4 bit 1)**: derived from a module-local "last-seen" timestamp that advances on each `zmk_peripheral_battery_state_changed` event. If no such event has been received in the last **10 seconds** AND `CONFIG_ZMK_SPLIT` is enabled, the firmware emits `0`; otherwise `1`. On fresh boot before any event, the timestamp is `0` → `right_online = 0` until the first event.
- **`has_split_link` capability bit (byte 0 bit 3)**: set to `1` ONLY when `IS_ENABLED(CONFIG_ZMK_SPLIT) && IS_ENABLED(CONFIG_ZMK_SPLIT_BLE)` — the two conditions that guarantee a split-sync bus exists for the right-online timestamp strategy to be meaningful. Integer boards (`CONFIG_ZMK_SPLIT=n`) set this to `0`, and `split_link_flags` bytes stay `0` (satisfying P-C1 and P-C2).

**Rationale**: At commit `6b44d33d`, `zmk_split_peripheral_status_changed` is defined BUT **raised only on the peripheral side** (`src/split/bluetooth/peripheral.c` L90/L108), not the central. On the central side, the "which peripheral is connected" information is stored privately in `central.c`'s `peripherals[]` array (slot state `PERIPHERAL_SLOT_STATE_CONNECTED`) with no public getter. The `transport_status_cb` callback mechanism (declared in `app/include/zmk/split/transport/central.h`) is private to the split subsystem.

The battery-event proxy approach is honest: the peripheral sends BAS updates to the central whenever its sync-bus is up (even without user config via the standard split protocol); if we haven't seen one in 10 s, the sync is likely down. This is proxy-indirect but **observable at the central**, requires no private API hacks, and degrades correctly to `right_online = 0` on real disconnection.

**Alternatives considered**:
- **Expose `has_split_link = 0` always on this pin**: rejected — defeats US1's split-halves row. Users with corne would see nothing on the split-link row; this feels like a worse user experience than the 10 s approximate detection.
- **Reach into `central.c`'s private `peripherals[]`**: rejected — breaks Zephyr module boundary; the symbol isn't exported.
- **Register as a split-transport status callback via `zmk_split_transport_central_set_status_callback_t`**: tempting but `transport_status_cb` is a `static` global in `central.c`; no public setter from outside the file at this commit.
- **Shorten the timeout to ~3 s** to match the host-side staleness rule (`001-connectivity-power` FR-015): rejected — ZMK's own BAS sync cadence can be slower than 3 s under heavy BLE load; 10 s is a safe lower bound. The host-side 3 s staleness rule applies independently (host measures wall-clock since last NOTIFY).

### R1.4 `output_endpoint`

**Decision**: subscribe to `zmk_endpoint_changed` from `<zmk/events/endpoint_changed.h>`. In the handler, call `zmk_endpoints_selected()` which returns `struct zmk_endpoint_instance { enum zmk_transport transport; ... }`. Map:
- `ZMK_TRANSPORT_USB` → wire value `1` (USB)
- `ZMK_TRANSPORT_BLE` → wire value `2` (BLE)
- Any other / unset (should not happen on this pin) → wire value `0` (unknown)

**Rationale**: both symbols present at pin (`app/include/zmk/endpoints.h`, `app/include/zmk/endpoints_types.h`). Enum has exactly 2 variants — no ambient "unknown" state in ZMK, so wire value `0` is used only during the brief pre-init window before the first endpoint resolution.

### R1.5 `charging_flags.bit 0` (left/overall) + `bit 1` (right)

**Decision**: emit `0` for both bits in all builds this release; `has_left_charging` + `has_right_charging` capability bits both `0`.

**Rationale**: approved in the pre-plan `AskUserQuestion` round (option "能力位 default 0,固件 emit 0 (推荐)"). No charger-GPIO plumbing is being introduced in this feature. A follow-up (v1.2.0 or board-overlay-driven) can add the per-board charger GPIO reading.

**Future hook (not implemented this release)**: a board-local `.overlay` can define `zephyr,user { keybeacon-charger-gpios = <&gpio ...>; };`; the module could read the GPIO via `DT_PROP`-level helper and `#if DT_HAS_...` guard. This is **out of scope** for v1.1.0 — the design note is only recorded so a reviewer sees the extensibility point.

### R1.6 `overall_battery` / `left_battery` / `right_battery`

**Decision**:
- **Central's own half**: subscribe to `zmk_battery_state_changed` (event struct carries `uint8_t state_of_charge`). On event, cache the value.
- **Peripheral(s)**: subscribe to `zmk_peripheral_battery_state_changed` (event carries `uint8_t source` + `uint8_t state_of_charge`). Cache by source index; emit source `0` as the "right half" byte for a 1-peripheral split (corne).
- **Which byte is which**:
  - Integer board (`CONFIG_ZMK_SPLIT=n`): 1-byte payload `[overall_percent]` where `overall_percent = zmk_battery_state_of_charge()` (or the last-cached event value).
  - Split (`CONFIG_ZMK_SPLIT=y`): 2-byte payload `[left_percent, right_percent]`. "Left" is the central's own reading (centrals in ZMK are conventionally the left half, matching corne's `corne_left` + `corne_right nice_view_adapter nice_view` build.yaml split).

**Rationale**: all four symbols (two events + two helpers) present at pin. The event-driven approach gives us the OR-relation side of §14.4.5 "≥ 1 pp change"; the ≥ 1 s floor is covered by a 1 Hz `k_work_delayable` that re-checks the cached payload against last-sent.

**Caveat on "central = left half"**: ZMK does not force central = left — the convention is build-config dependent. For the user's corne, `build.yaml` shows the left half is the central (`corne_left ... snippet: studio-rpc-usb-uart`), matching convention. A build where the central is physically the right half will mis-label the halves on the wire. **This is out of scope** for v1.1.0; it's a known limitation documented in the quickstart (SC-002 verification scenario uses the user's corne where central = left).

**Sentinel `255`**: emitted when `zmk_split_central_get_peripheral_battery_level(0, &level)` returns `-EINVAL` (sync bus down) OR when no `zmk_peripheral_battery_state_changed` event has fired since boot. Satisfies FR-B5 + P-B3 of protocol §14.4.3.

## R2. Throttling design (§14.4.5)

**Decision**: single 1 Hz `k_work_delayable` posted at module init, re-schedules itself every 1 s. On each tick:

1. Rebuild the Battery payload from current cached values.
2. Compare to last-sent cached payload.
3. If different → NOTIFY, update cache, update "last emit timestamp".
4. If identical AND it has been ≥ 1 s since last emit → still check if any byte-value delta is pending (should not happen since the cache compares byte-for-byte; the ≥ 1 s floor is only relevant when sub-pp drift exists, which §14.4.5 explicitly handles via the OR relation).

Separately, the two battery-event handlers (`zmk_battery_state_changed`, `zmk_peripheral_battery_state_changed`) also:

1. Update their respective cached percent.
2. If byte differs from last-sent by ≥ 1 → NOTIFY immediately (without waiting for the 1 Hz tick).

**Rationale**: the OR relation is literally `(diff ≥ 1) OR (elapsed ≥ 1 s)` — the event path covers condition A, the 1 Hz worker covers condition B. Snapshot-unchanged suppression is handled by the "compare to last-sent cached payload" check in both paths.

**Alternative considered**: single 1 Hz worker that handles both change-detection and the time floor. Rejected because event-driven path has lower latency on real change (immediate NOTIFY vs up to 1 s delay).

## R3. Connectivity payload build strategy

**Decision**: pack the 7 bytes into a `struct __packed { uint8_t capability_bits; uint8_t host_state; uint8_t profile_index; uint8_t profile_max_slots; uint8_t split_link_flags; uint8_t output_endpoint; uint8_t charging_flags; }` inside the module, use `BUILD_ASSERT(sizeof(conn_payload_t) == 7, ...)`. Payload is rebuilt from scratch on each event (no partial updates — simpler and deterministic).

**Rationale**: Zephyr uses little-endian for ARM targets natively; `__packed` on an all-uint8 struct is a no-op layout-wise but documents intent. `BUILD_ASSERT` catches any accidental field addition that would push the struct beyond 7 bytes before KBP 1.2 is published.

**`capability_bits` computation (constant per build)**:

```c
#define KEYBEACON_CAP_IS_SPLIT          (IS_ENABLED(CONFIG_ZMK_SPLIT) ? 0x01u : 0)
#define KEYBEACON_CAP_HAS_HOST_CONN     0x02u
#define KEYBEACON_CAP_HAS_PROFILE       0x04u
#define KEYBEACON_CAP_HAS_SPLIT_LINK    ((IS_ENABLED(CONFIG_ZMK_SPLIT) && \
                                          IS_ENABLED(CONFIG_ZMK_SPLIT_BLE)) ? 0x08u : 0)
#define KEYBEACON_CAP_HAS_OUT_ENDPOINT  0x10u
#define KEYBEACON_CAP_HAS_LEFT_CHARGING 0  /* v1.1.0: no charger GPIO support */
#define KEYBEACON_CAP_HAS_RIGHT_CHARGING 0 /* v1.1.0: no charger GPIO support */

static const uint8_t keybeacon_cap_bits =
    KEYBEACON_CAP_IS_SPLIT | KEYBEACON_CAP_HAS_HOST_CONN | KEYBEACON_CAP_HAS_PROFILE |
    KEYBEACON_CAP_HAS_SPLIT_LINK | KEYBEACON_CAP_HAS_OUT_ENDPOINT;
```

This is baked into every emitted Connectivity payload byte 0 — no runtime cost, cannot drift.

## R4. `#if defined`-guards for optional ZMK APIs (FR-K3)

For each API that might be missing on an older/different ZMK tree, the module uses a guard. At the pinned commit all are present, so the guards degrade to no-ops.

| API | Guard | Degradation if absent |
|-----|-------|-----------------------|
| `zmk_endpoint_changed` + `zmk_endpoints_selected()` | `#if __has_include(<zmk/endpoints.h>)` | Byte 5 stays `0`; cap bit `has_output_endpoint` = `0` |
| `zmk_split_central_get_peripheral_battery_level` | `#if IS_ENABLED(CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING)` | Right byte of split battery = `255`; still correct per §14.4.2 |
| `zmk_peripheral_battery_state_changed` | `#if __has_include(<zmk/events/battery_state_changed.h>)` + presence of `struct zmk_peripheral_battery_state_changed` | Right-online stays `0` (10 s timeout path never advances); right battery byte stays `255` |

**Rationale**: `__has_include` is C23 but Zephyr toolchain (`arm-zephyr-eabi-gcc` ≥ 10) supports it as a GCC extension; portable alternative is a Kconfig-level check. The module will prefer `IS_ENABLED(CONFIG_...)` guards where the ZMK symbol has a Kconfig and `__has_include` only for header-only hints.

## R5. CMake / Kconfig integration

**Decision**: both Kconfig additions go into the **existing** `Kconfig.keybeacon` with no new file. `keybeacon.cmake` stays unchanged (the existing `zephyr_library()` block already picks up all `.c` files under the current directory via `zephyr_library_sources(${CMAKE_CURRENT_LIST_DIR}/keybeacon.c)` — and we are not adding new files).

```kconfig
# Kconfig.keybeacon (post-change)
config ZMK_KEYBEACON
    bool "KeyBeacon: expose keyboard status (layer+mods) over a custom GATT characteristic"
    depends on ZMK_BLE
    default n

config ZMK_KEYBEACON_CONNECTIVITY
    bool "KeyBeacon 1.1: expose Connectivity characteristic (AA440AA2-…)"
    depends on ZMK_KEYBEACON
    default y
    help
      Emit host-connection, profile, split-link, output-endpoint, and charging-flag
      state on an additional GATT characteristic under the KeyBeacon service.
      See KBP 1.1 §14.3 at
      https://github.com/ykiewang/keybeacon/tree/main/protocol#143-connectivity-characteristic-payload
      for the wire contract.

config ZMK_KEYBEACON_BATTERY
    bool "KeyBeacon 1.1: expose Battery characteristic (AA440AA3-…)"
    depends on ZMK_KEYBEACON
    default y
    help
      Emit battery percent(s) on an additional GATT characteristic. Payload is 1 byte
      overall on integer boards, 2 bytes [left, right] on splits. 255 = read failed
      / temporarily unavailable. See KBP 1.1 §14.4.
```

**Rationale**: both Kconfig symbols are additive and have the parent `ZMK_KEYBEACON` as a `depends on`, so they vanish from menuconfig when the parent is `n`. `default y` makes `v1.1.0` opt-in by default under `CONFIG_ZMK_KEYBEACON=y` (user's chosen policy).

## R6. Resolved NEEDS CLARIFICATION items

| Original uncertainty | Resolution |
|----------------------|------------|
| Exact ZMK API names on `zmk@6b44d33d` | Verified via local `git show`; see §R1.1–R1.6 above. All six §14.8 symbols map 1:1 except `zmk_split_bt_peripheral_status_changed` (that's protocol-doc naming; actual symbol is `zmk_split_peripheral_status_changed` and is peripheral-side only — use the battery-event proxy strategy per §R1.3). |
| How to detect peripheral online from central at this pin | Battery-event proxy with 10 s timeout; `has_split_link` cap bit also gated on `CONFIG_ZMK_SPLIT_BLE=y`. |
| Where to add the 1 Hz throttling worker | Single `k_work_delayable`, posted in the module's `SYS_INIT`, re-schedules every 1 s. |
| Whether to split `keybeacon.c` into three files | Keep single-file; see plan.md "Structure Decision". |

All NEEDS CLARIFICATION items resolved. **No open questions remain for Phase 1.**
