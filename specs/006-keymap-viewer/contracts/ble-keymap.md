# Contract: BLE Keymap Characteristics (KBP 1.3)

**Status**: Draft | **Date**: 2026-11-26

This contract governs `KeymapMeta` and `KeymapData`, the two optional GATT characteristics added in KBP 1.3. Once ratified, this file is copied verbatim into `keybeacon/protocol/README.md` §1.3.

## Service UUID

Unchanged from KBP 1.0:

```
AA440AA0-F5ED-4C48-84A1-8062D20D3D55
```

## KeymapMeta Characteristic

**UUID**: `AA440AA5-F5ED-4C48-84A1-8062D20D3D55`

**Properties**: READ only. No NOTIFY, no CCC descriptor.

**Payload layout** (little-endian throughout):

| Offset | Size | Type | Field |
|--------|------|------|-------|
| 0 | 4 | uint32_t LE | `crc32` — CRC32/IEEE 802.3 of the full `KeymapData` payload |
| 4 | 1 | uint8_t | `layer_count` — number of layers (1–255) |
| 5 | 2 | uint16_t LE | `key_count` — number of physical keys |
| 7 | var | UTF-8 | `layer_names` — layer name strings, each NUL-terminated (`\0`); last name also NUL-terminated |

The total `KeymapMeta` payload length is `7 + sum(len(name_i) + 1)` bytes.

A host MUST read `KeymapMeta` once after connecting to determine whether the local `KeymapData` cache is still valid. If `crc32` equals the cached value for this peripheral UUID, the host MAY skip reading `KeymapData`.

## KeymapData Characteristic

**UUID**: `AA440AA6-F5ED-4C48-84A1-8062D20D3D55`

**Properties**: READ only, with ATT READ_BLOB support (opcode 0x0C). No NOTIFY, no CCC descriptor.

The payload is a flat binary buffer with two contiguous segments:

### Segment 1 — Physical Layout (`key_entry` array)

One `key_entry` per physical key, in key-index order (0 … key_count−1):

```
struct key_entry {           // 10 bytes, packed, little-endian
    int16_t  x;   // 0.01u — left edge of key bounding box
    int16_t  y;   // 0.01u — top edge of key bounding box
    uint8_t  w;   // 0.1u  — width
    uint8_t  h;   // 0.1u  — height
    int16_t  r;   // 0.01° — clockwise rotation angle
    int16_t  rx;  // 0.01u — rotation-origin x (absolute)
    int16_t  ry;  // 0.01u — rotation-origin y (absolute)
};
```

Unit reference: 1u = 54pt on screen (applied by the host renderer).

### Segment 2 — Keycode Table (`binding_entry` array)

Layer-major, key-minor order: all keys of layer 0, then all keys of layer 1, etc.

```
struct binding_entry {       // 5 bytes, packed, little-endian
    uint8_t  behavior_id;
    uint16_t param1;
    uint16_t param2;
};
```

**Total payload size**: `10 × key_count + 5 × layer_count × key_count` bytes.

### ATT READ_BLOB Protocol

A host reads `KeymapData` using successive ATT READ_BLOB requests (opcode 0x0C), incrementing the offset by the number of bytes received each round, until the firmware returns an empty payload (0 bytes) or an ATT error indicating the offset is at or past the end. The host reassembles all chunks in order.

The firmware uses `bt_gatt_attr_read(conn, attr, buf, len, offset, data, data_len)`, which handles the offset slicing automatically.

### behavior_id Enum

| Value | Symbol | ZMK behavior |
|-------|--------|-------------|
| 0x01 | KP | `&kp` |
| 0x02 | MT | `&mt` |
| 0x03 | LT | `&lt` |
| 0x04 | MO | `&mo` |
| 0x05 | TO | `&to` |
| 0x06 | TOG | `&tog` |
| 0x07 | SL | `&sl` |
| 0x08 | SK | `&sk` |
| 0x09 | TRANS | `&trans` |
| 0x0A | NONE | `&none` |
| 0x0B | KEY_REPEAT | `&key_repeat` |
| 0x0C | GRESC | `&gresc` |
| 0x0D | CAPS_WORD | `&caps_word` |
| 0x0E | KT | `&kt` |
| 0x10 | TD | `&td` |
| 0x11 | MACRO | `&macro` / `&macro_one_param` / `&macro_two_param` |
| 0x12 | MOD_MORPH | `&mod_morph` |
| 0x20 | BT | `&bt` |
| 0x21 | OUT | `&out` |
| 0x22 | RESET | `&sys_reset` |
| 0x23 | BOOTLOADER | `&bootloader` |
| 0x30 | MKP | `&mkp` |
| 0x40 | RGB | `&rgb_ug` |
| 0x41 | BL | `&bl` |
| 0x42 | EXT_POWER | `&ext_power` |
| 0x43 | SOFT_OFF | `&soft_off` |
| 0x44 | STUDIO_UNLOCK | `&studio_unlock` |
| 0xFF | UNKNOWN | any unrecognised behavior |

## Capability Detection

A host MUST determine KBP 1.3 support by enumerating GATT characteristics after connection: if `AA440AA5` is present, the keyboard supports `KeymapMeta`; if `AA440AA6` is present, it supports `KeymapData`. The host MUST NOT gate on device name, model, or vendor.

## Backward Compatibility

- Old hosts that do not know `AA440AA5`/`AA440AA6` ignore those handles and behave as KBP 1.2.
- New hosts that do not find `AA440AA5` MUST disable the keymap viewer UI entirely (grey out menu item).
- The KBP service UUID is unchanged; the MINOR version signal is the presence of new characteristics, not a version field.

## Fallback: Missing Physical Layout

If the firmware has no `physical_layout` Devicetree node, it MUST substitute a linear fallback: key `i` gets `x = i×100, y = 0, w = 10, h = 10, r = rx = ry = 0`. The host renders this as a single row of equal-width keys.
