# Contract: Kconfig interface

**Feature**: 002-zmk-keybeacon-kbp11

**Scope**: the Kconfig surface the module exposes to its consumer (`zmk-config-<keyboard>/config/*.conf`).

## 1. Existing symbol (unchanged by this feature)

```kconfig
config ZMK_KEYBEACON
    bool "KeyBeacon: expose keyboard status (layer+mods) over a custom GATT characteristic"
    depends on ZMK_BLE
    default n
```

Semantics unchanged from v1.0.0. Setting `CONFIG_ZMK_KEYBEACON=y` enables the entire KeyBeacon service and its characteristics (subject to the sub-options below).

## 2. New symbols (added by this feature)

```kconfig
config ZMK_KEYBEACON_CONNECTIVITY
    bool "KeyBeacon 1.1: expose Connectivity characteristic (AA440AA2-…)"
    depends on ZMK_KEYBEACON
    default y
    help
      Emit host-connection, profile, split-link, output-endpoint, and charging-flag
      state on an additional GATT characteristic under the KeyBeacon service. See
      KBP 1.1 §14.3 for the wire contract.

config ZMK_KEYBEACON_BATTERY
    bool "KeyBeacon 1.1: expose Battery characteristic (AA440AA3-…)"
    depends on ZMK_KEYBEACON
    default y
    help
      Emit battery percent(s) on an additional GATT characteristic. Payload is
      1 byte overall on integer boards, 2 bytes [left, right] on splits.
      255 = read failed / temporarily unavailable. See KBP 1.1 §14.4.
```

## 3. Semantic matrix (all combinations)

| `ZMK_KEYBEACON` | `_CONNECTIVITY` | `_BATTERY` | GATT exposure |
|---|---|---|---|
| `n` | * | * | **no service** — module is not compiled in |
| `y` | `n` | `n` | AA1 only (KBP 1.0 behavior; AA2/AA3 absent — matches `revision: v1.0.0` output) |
| `y` | `y` | `n` | AA1 + AA2 (connectivity, no battery) |
| `y` | `n` | `y` | AA1 + AA3 (battery, no connectivity — unusual but legal) |
| `y` | `y` | `y` | AA1 + AA2 + AA3 (full KBP 1.1) — **default under `CONFIG_ZMK_KEYBEACON=y`** |

**Guarantee**: a build with `ZMK_KEYBEACON=y, _CONNECTIVITY=n, _BATTERY=n` is **byte-indistinguishable at the GATT layer** from a `revision: v1.0.0` module build (same service, same single AA1 characteristic, same CCC). SC-005 verification point.

## 4. Dependency on other Kconfigs

- `ZMK_KEYBEACON` already `depends on ZMK_BLE` (unchanged); the sub-options inherit this.
- `ZMK_KEYBEACON_BATTERY`'s split-right-byte emission additionally benefits from `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y`, which is **not** declared as `select`-based or `depends on`-based because the module degrades correctly (right byte = 255) when it's absent. Documenting the dependency relationship:

| Downstream build intent | Recommended Kconfig combination |
|--------------------------|------------------------------------|
| 1.0-only firmware | `CONFIG_ZMK_KEYBEACON=y` (sub-options irrelevant with default-y under disabled parent) |
| 1.1 Connectivity only, no Battery (minimal binary growth) | `CONFIG_ZMK_KEYBEACON=y`, `CONFIG_ZMK_KEYBEACON_BATTERY=n` |
| 1.1 full | `CONFIG_ZMK_KEYBEACON=y` (defaults OK; or explicitly `CONFIG_ZMK_KEYBEACON_CONNECTIVITY=y`, `CONFIG_ZMK_KEYBEACON_BATTERY=y`) |
| 1.1 full on a split keyboard with per-half battery | add `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y` to the recommended set (ZMK provides this upstream) |

## 5. Keyboard-author upgrade path

**From v1.0.0 to v1.1.0** (for a user already using the module):

1. Edit `config/west.yml`: `revision: v1.0.0` → `revision: v1.1.0`.
2. Run `west update`.
3. Run `west build` for the **central** target.
4. Flash.

No `.conf` changes required. Both new characteristics appear automatically because both sub-options `default y`.

**To opt out of 1.1 (keep 1.0 behaviour on the v1.1.0 module)**:

1. Same steps 1–2 above.
2. Add to the central `.conf`:
   ```conf
   CONFIG_ZMK_KEYBEACON_CONNECTIVITY=n
   CONFIG_ZMK_KEYBEACON_BATTERY=n
   ```
3. Build + flash.

## 6. Mapping back to feature spec

| FR / SC | Covered by this contract |
|---------|--------------------------|
| FR-K1 | sections 2 + 4 |
| FR-K2 | the matrix in section 3 is reproducible with the user's corne west manifest |
| FR-K3 | not covered here (that's about ZMK-API absence, not Kconfig-presence); see `research.md §R4` |
| SC-005 | section 3 "byte-indistinguishable" guarantee |
| US3 (backward compat) | section 5 upgrade path |

## 7. Backward compatibility guarantee

- `ZMK_KEYBEACON=n` → module not compiled. Zero wire change.
- `ZMK_KEYBEACON=y` + both sub-options `n` → equivalent to v1.0.0 module build. **Byte-equivalent on GATT.**
- `ZMK_KEYBEACON=y` + sub-options `y` → KBP 1.1 full. KBP 1.0 hosts still see AA1 identical to v1.0.0 (they ignore AA2/AA3 which they never subscribe to).
