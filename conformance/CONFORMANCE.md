# Making a keyboard conform to KeyBeacon (KBP)

This guide is the **complete, concrete body of work** to make a keyboard work with KeyBeacon and
to prove it. It is normative for the claim "this keyboard supports KBP". The authoritative wire
contract is [`../protocol/README.md`](../protocol/README.md); this document tells a keyboard author
**what to build**, and [`checklist.md`](checklist.md) + [`conformance_tool.py`](conformance_tool.py)
tell them **how to verify** it.

You can implement KBP on any firmware stack and any BLE library — KBP is defined only by what
appears on the air. The notes below call out the ZMK reference path where helpful, but nothing here
requires ZMK.

## 0. Prerequisite: the keyboard must own the host BLE link (central role)

KeyBeacon reports state to a desktop host over the keyboard's **host-facing BLE connection**. The
keyboard must therefore be the device the host connects to:

- **Unibody / single-MCU keyboard**: it already is the host-link device — nothing special.
- **Split keyboard**: only the half that holds the **central (host-link) role** exposes KeyBeacon.
  The peripheral half and any `settings_reset`/recovery image **must not** include it. (In the ZMK
  reference, that means the KeyBeacon kit is gated to the central build only.)

If your keyboard cannot act as the host-link BLE device, it cannot implement KBP as specified.

## 1. Expose the service and characteristic

Add one custom GATT **primary service** with one **status characteristic**:

| Item | Value |
|------|-------|
| Service UUID | `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` |
| Status characteristic UUID | `AA440AA1-F5ED-4C48-84A1-8062D20D3D55` |
| Properties | `READ` **and** `NOTIFY` |
| Descriptor | Client Characteristic Configuration (CCC, `0x2902`) — required for NOTIFY |

The **service UUID is the identity and the compatibility signal**. Do not gate behavior on device
name or model. (Verified by tool check **C1**.)

## 2. Produce the status payload (≥ 2 bytes, little-endian)

The characteristic value is the variable-length snapshot from protocol §4:

| Offset | Size | Field | Source |
|--------|------|-------|--------|
| `[0]` | 1 | `layer_index` (`uint8`) | highest active layer index |
| `[1]` | 1 | `mods` (`uint8`) | held HID modifier bitmask (see §4.1) |
| `[2..N]` | ≥ 0 | `layer_name` (UTF-8, no trailing NUL) | active layer's name; MAY be empty |

Rules:

- The payload MUST be **at least 2 bytes**. `layer_name` MAY be empty (a 2-byte payload is valid).
- `layer_name` MUST be **valid UTF-8** and carry **no trailing NUL**.
- Derive everything from the keyboard's authoritative keymap/HID state — never a second cached copy.
- Keep the whole snapshot within your negotiated ATT MTU (the reference firmware truncates
  `layer_name` to 32 bytes; that is an implementation limit, not a protocol limit).

(Verified by tool check **C2**.)

## 3. Notify on change, and suppress when unchanged

- Send a **NOTIFY** whenever the snapshot changes (a layer switch or a modifier press/release).
- **Suppress** the notification when the recomputed snapshot equals the last one you sent. An idle
  keyboard MUST produce **zero** notification traffic.
- Support **READ** for the current snapshot (the host reads it once on connect, then subscribes).

(Verified by tool check **C3**: subscription succeeds and no traffic arrives while idle.)

## 4. Stay discoverable while connected

A connected BLE HID keyboard stops advertising, so the host finds it by **enumerating already-
connected peripherals** and confirming the service over GATT. You get this for free by exposing the
service on the live host connection — just make sure the service is present on the **connected**
image. (Verified by tool check **C4** when the keyboard is connected to the test host.)

## 5. Advertise a GAP device name (recommended)

Advertise a non-empty **GAP device name**; the host uses it as the display name. If absent, the host
falls back to a generic label and still connects, so this is **RECOMMENDED, not required**.
(Reported by tool check **C5**; the tool prints the discovered name so you can confirm identity.)

## 6. Verify with the conformance tool

Run the self-test against your keyboard (connect it to the test Mac first for the reliable path):

```bash
python3 conformance/conformance_tool.py            # defaults: --timeout 15 --observe 4
```

The tool discovers your keyboard **by service UUID only**, prints the discovered GAP name, and
reports **per-item PASS/FAIL/WARN** for C1–C6 (see [`checklist.md`](checklist.md)).

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | all required items pass — the keyboard conforms to KBP 1.x |
| `1` | a required conformance item failed (the output names which one) |
| `2` | environment error — Bluetooth off, no keyboard found, connect timeout, or missing deps |

Required items are **C1–C4**; **C5** is RECOMMENDED (WARN only) and **C6** (split central-only) is a
MANUAL firmware-config check the host cannot observe. A clean reference keyboard yields exit `0`.

## 7. Requirements for the tool

macOS with Python 3 and PyObjC CoreBluetooth:

```bash
pip install pyobjc-framework-CoreBluetooth
```

Grant the terminal/app Bluetooth permission when macOS prompts.
