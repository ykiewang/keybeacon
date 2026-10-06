# KBP 1.x conformance checklist

Each line is an **individually verifiable** requirement from KeyBeacon Protocol §10. The right
column names the automated check in [`conformance_tool.py`](conformance_tool.py) that covers it.
Build guidance for each item is in [`CONFORMANCE.md`](CONFORMANCE.md); the wire contract is
[`../protocol/README.md`](../protocol/README.md).

A keyboard **conforms to KBP 1.x** when every REQUIRED item passes.

| # | Requirement | Level | Tool check |
|---|-------------|-------|-----------|
| 1 | Exposes service `AA440AA0-F5ED-4C48-84A1-8062D20D3D55` with characteristic `AA440AA1-…`, properties `READ`+`NOTIFY`, and a CCC (`0x2902`) descriptor. | REQUIRED | **C1** |
| 2 | A READ returns a snapshot **≥ 2 bytes** matching the `[layer_index][mods][layer_name]` layout; `layer_name` is valid UTF-8 (or empty) with no trailing NUL. | REQUIRED | **C2** |
| 3 | NOTIFY fires on every layer/modifier change **and is suppressed when the snapshot is unchanged** (an idle keyboard emits zero notifications). | REQUIRED | **C3** |
| 4 | Remains discoverable **while connected** via connected-peripheral enumeration (it has stopped advertising once connected to the host). | REQUIRED | **C4** |
| 5 | Advertises a **non-empty GAP device name** (else the host uses a generic fallback). | RECOMMENDED | **C5** (WARN) |
| 6 | For split keyboards: the feature is present **only on the central (host-link) role** and absent from the peripheral and `settings_reset` images. | REQUIRED (split) | **C6** (MANUAL) |

## How verification maps to results

- **C1–C4** gate the exit code: any FAIL ⇒ the tool exits `1` and names the failing item.
- **C5** is RECOMMENDED — a missing GAP name is reported as **WARN**, not a failure.
- **C6** cannot be observed from the host; the tool marks it **MANUAL**. Confirm in your firmware
  build config that the KeyBeacon service is compiled into the **central** image only.
- Environment problems (Bluetooth off, no keyboard, connect timeout, missing PyObjC) exit `2` — a
  tooling/setup issue, not a conformance verdict.

## Quick self-test

```bash
python3 conformance/conformance_tool.py
# exit 0 = conforms · 1 = a required item failed · 2 = environment error
```
