# Quickstart — zmk-keybeacon v1.1.0 verification

**Feature**: 002-zmk-keybeacon-kbp11

**Date**: 2026-10-09

Purpose: hands-on validation of the module's KBP 1.1 implementation on the user's **Corne** hardware. Each scenario maps to one or more FR / SC IDs in `spec.md`. Scenarios A–E are the primary acceptance set; F covers the Kconfig matrix of §US3; G is the regression gate against KBP 1.0 hosts.

**Prerequisites (one-time)**:

- Two git repos checked out side-by-side (per `plan.md` structure note):
  - `/Users/wangyuting19/kbd/keybeacon/keybeacon` on branch `001-connectivity-power` (the KBP 1.1 host app + conformance tool with 1.1 checks)
  - `/Users/wangyuting19/kbd/keybeacon/zmk-keybeacon` on branch `feat/kbp-1.1-connectivity-power` (this feature's implementation)
- `zmk-config-corne` checkout at `/Users/wangyuting19/kbd/zmk-config-corne` on branch `feat/keybeacon`.
- Local ZMK at `/Users/wangyuting19/kbd/zmk` (used for API verification; `west update` on corne will fetch the pinned commit `6b44d33d` into the corne build tree).
- Python 3 with `bleak` installed: `python3 -m pip install -U -r conformance/requirements.txt` (run inside the keybeacon main repo).
- macOS Bluetooth permission granted to the terminal / Python.
- Corne central (`corne_left nice_view_adapter nice_epaper`) flashed with the firmware under test; peripheral half (`corne_right`) paired.

**Verification identity**:

- The Mac's `conformance_tool.py` is the ground truth for exit code + per-check PASS/WARN/FAIL/SKIP (C7–C12).
- The macOS KeyBeacon app's "连接与电量" card is the ground truth for user-observable rendering.
- `log stream --predicate 'subsystem == "com.keybeacon.app"'` is the diagnostics channel for the host side.

---

## Interim west.yml override (temporary, never committed)

For local verification before tagging v1.1.0, edit `config/west.yml` in the corne config:

```yaml
    - name: zmk-keybeacon
      path: ../zmk-keybeacon        # <-- relative to the west.yml file's directory
      # revision: v1.0.0            # <-- commented out; use local path
```

Then `west update` picks up the local module. **Revert to `revision: v1.1.0`** once the module is tagged (see Scenario F).

---

## Scenario A — baseline 1.1 end-to-end

**Validates**: SC-001, FR-G1, FR-G2, FR-C1–C2–C4, US1 acceptance scenarios 1 + 2 + 3.

**Given**:
- Corne central is flashed with the v1.1.0 firmware (both sub-Kconfigs `default y`, no `.conf` opt-out).
- Peripheral is paired.
- Corne is connected to the Mac over BLE.

**When**:
```bash
cd /Users/wangyuting19/kbd/keybeacon/keybeacon
python3 conformance/conformance_tool.py --timeout 15
```

**Then** (expected output):
- Exit code `0`.
- `declared_minor: 1.1`.
- `characteristics.AA440AA2.present: true`, `characteristics.AA440AA3.present: true`.
- `C7 PASS` (AA2 properties = READ|NOTIFY+CCC).
- `C8 PASS` (payload ≥ 7 bytes, P-C1..P-C5 all hold; `capability_bits = 0x1F` on corne).
- `C9 PASS` (AA3 properties + 2-byte payload).
- `C10 PASS` (NOTIFY on change observed during `--observe 4`).
- `C11 PASS` or `WARN` (battery throttling; WARN only if sub-pp jitter without hardware justification).
- `C12 MANUAL` (central-only split — the tool reports MANUAL, not FAIL; verify manually that peripheral image doesn't link `keybeacon.c`).

**Diagnostic log (host side, during the run)**:
```bash
log stream --predicate 'subsystem == "com.keybeacon.app"' --level info
# expected: capability.enumerated events listing is_split=1, has_split_link=1, etc.
```

**If FAIL** on any of C7–C11:
1. Record the exact `check_us*` message from the tool's output.
2. Compare the raw payload bytes (`conformance_tool.py --json | jq '.frames'`) against the contract in `contracts/connectivity-characteristic.md §2`.
3. Common failure modes:
   - P-C3 violated (profile_index > profile_max_slots) → likely a 0-based vs 1-based bug in the module; check `data-model.md E1` byte `[2]` encoding.
   - Reserved bits non-zero → check the clamps on each field.

---

## Scenario B — output endpoint toggle latency

**Validates**: SC-002 (≤ 1 s host render update × 10 trials), FR-C6, US1 acceptance scenario 2.

**Given**: Scenario A setup; macOS KeyBeacon app running and showing the "Output endpoint: BLE" row.

**When** (repeat 10 times):
1. On the corne, press the on-keyboard shortcut that cycles output endpoint (`Mo+Fn+O` in the corne keymap, or whatever is bound to `&out OUT_TOG` in `corne.keymap`).
2. Immediately start a stopwatch (or use wall-clock from the keyboard log).
3. Watch the app's "Output endpoint" row.
4. Stop the stopwatch when the row changes to "USB" (or "BLE" on alternate trials).

**Then**:
- All 10 trials show ≤ 1 second between keypress and app row update.
- `conformance_tool.py --observe 4` (background, in a second terminal) records a NOTIFY on `AA440AA2-…` within ≤ 100 ms of each keypress.
- No connection drops; no "stale" badge appears on the row.

**Observation strategy for `--observe 4`**:
```bash
# second terminal
python3 conformance/conformance_tool.py --observe 10 --json | tee /tmp/observe.json
# then: jq '.frames[] | select(.characteristic | contains("AA440AA2"))' /tmp/observe.json
```

---

## Scenario C — peripheral unpair → split-link flip

**Validates**: FR-C5, US1 acceptance scenario 3, research.md §R1.3 (10 s TTL on `right_online`).

**Given**: Scenario A setup; both halves paired and the app shows "split halves: both online".

**When**:
1. On the right half (peripheral), hold reset for 5 s to unpair (or disconnect by battery removal).
2. Watch the app's "split halves" row.

**Then**:
- Within ≤ 10 seconds (worst case of the TTL plus a 1 Hz tick), the right half's indicator flips to offline.
- `conformance_tool.py --observe` records a NOTIFY on `AA440AA2-…` where byte `[4]` (`split_link_flags`) transitions from `0x03` → `0x01`.
- Re-pairing the peripheral causes the reverse transition within ≤ 1 s (immediate: the next `zmk_peripheral_battery_state_changed` event advances `peripheral_slots[0].last_seen_ms`).

**Known approximation**: because the module uses a battery-event proxy (research.md §R1.3), the "offline" detection latency is bounded by `10 s TTL + 1 s worker interval ≈ 11 s`. Faster detection would require a public central-side status API that doesn't exist at the pinned ZMK commit.

---

## Scenario D — battery throttling

**Validates**: SC-003 (≤ 60 NOTIFY in 60 s continuous typing), FR-B3, US2 acceptance scenario 2.

**Given**: Scenario A setup; `--observe 60` ready to run.

**When**:
```bash
# terminal 1: start observation
python3 conformance/conformance_tool.py --observe 60 --json > /tmp/batt60.json

# terminal 2: on the keyboard, type continuously for 60 seconds (any text input works;
# the goal is high keyboard activity to generate sub-pp battery jitter)
```

**Then**:
- `jq '[.frames[] | select(.characteristic | contains("AA440AA3"))] | length' /tmp/batt60.json` returns ≤ 60.
- Each NOTIFY carries a payload where some byte differs from the previous emission (change-suppression discipline).
- No NOTIFY carries a byte value in `101..254` (reserved values forbidden by FR-B2).

---

## Scenario E — peripheral battery read failure (sentinel)

**Validates**: FR-B5, US2 acceptance scenario 3.

**Given**: Scenario A setup; app shows a live right-half battery reading (e.g. 72%).

**When**: power off the right half (remove battery or hold power-off key for a long time).

**Then**:
- Within ≤ 10 s (bounded by E2's TTL), the module's internal `peripheral_slots[0].last_seen_ms` becomes stale.
- The next 1 Hz tick rebuilds the Battery payload. The right byte is now treated as "no fresh data": the module emits `255`.
- `conformance_tool.py --observe` records a NOTIFY on `AA440AA3-…` with byte `[1] = 0xFF`.
- The app's right-half `BatteryBarView` renders as "read failed" per `001-connectivity-power` host spec `C-B3`.
- Re-powering the right half restores a normal reading within ≤ 2 s of first sync-bus message.

---

## Scenario F — Kconfig matrix (opt-out verification)

**Validates**: SC-005, US3 acceptance scenarios 1 + 2 + 3.

**Given**: three corne central builds (A), (B), (C):

- **(A)** `west.yml revision: v1.0.0` (original v1.0.0 module, unchanged `.conf`).
- **(B)** `west.yml revision: v1.1.0` (or local path override), unchanged `.conf` (both sub-Kconfigs `default y`).
- **(C)** `west.yml revision: v1.1.0` + add `CONFIG_ZMK_KEYBEACON_CONNECTIVITY=n` and `CONFIG_ZMK_KEYBEACON_BATTERY=n` to `config/corne.conf`.

**When** (for each build):
```bash
# flash the central
west build -b nice_nano_v2 -p always -- -DSHIELD="corne_left nice_view_adapter nice_epaper" -S studio-rpc-usb-uart
cp build/zephyr/zmk.uf2 /Volumes/NICENANO/
# wait for the keyboard to re-pair, then:
cd /Users/wangyuting19/kbd/keybeacon/keybeacon
python3 conformance/conformance_tool.py --timeout 15 --json > /tmp/build_<A|B|C>.json
```

**Then**:
- (A): exit `0`; `declared_minor: 1.0`; `characteristics.AA440AA2.present: false`; `characteristics.AA440AA3.present: false`.
- (B): exit `0`; `declared_minor: 1.1`; both AA2 and AA3 present (same as Scenario A).
- (C): exit `0`; `declared_minor: 1.0`; same AA2/AA3 absent profile as (A). **This is the SC-005 "byte-indistinguishable" gate.**

**Byte-level verification between (A) and (C)**:
```bash
diff <(jq '.characteristics' /tmp/build_A.json) <(jq '.characteristics' /tmp/build_C.json)
# expected: empty (identical GATT shape)
```

---

## Scenario G — KBP 1.0 host regression (zero behaviour change)

**Validates**: SC-004, FR-G1, US1 acceptance scenario 4.

**Given**:
- A pre-`001-connectivity-power` build of the macOS KeyBeacon app (a KBP 1.0 host that doesn't subscribe to AA2/AA3).
- Corne central running the v1.1.0 firmware from Scenario A.

**When**:
1. Launch the pre-1.1 app binary.
2. Use the keyboard normally for 10 minutes (layer switches, modifier presses, typing).
3. In parallel, run `conformance_tool.py --observe 600 --json` and capture all NOTIFYs.

**Then**:
- Layer + modifier display in the app updates bit-for-bit identically to a v1.0.0 firmware run.
- `jq '[.frames[] | select(.characteristic | contains("AA440AA2"))] | length' /tmp/g_observe.json` returns `0` — the KBP 1.0 host never enabled the CCC, so firmware emits nothing on AA2.
- Same for AA3.
- No disconnects beyond baseline BLE noise.

**If AA2/AA3 NOTIFYs are seen**: that's a bug — the firmware is NOTIFYing before CCC is enabled, which violates Zephyr GATT semantics. Check that `bt_gatt_notify(NULL, ...)` is only called **after** at least one subscriber enables CCC (or let Zephyr's own CCC-gating handle it, which it does by design).

---

## Reference-keyboard note (constitution Testing Discipline)

The project constitution requires "at least one scenario per feature MUST be reproducible with the reference keyboard (currently Totem)". For this feature, the primary reference becomes **Corne** (the user's hardware) because:

- Totem was the historical reference for KBP 1.0; the user has moved to Corne for 1.1 verification.
- The 1.1 scenarios A–G all exercise split-centric paths (profile, split_link, battery per half) that Totem (if an integer board) could not cover.
- Corne's `build.yaml` is a standard split layout that other split keyboard authors can mirror.

If a reader has access to a Totem (integer or ZMK-split), Scenarios A, B, D, F should still work with trivial substitutions. Scenario C/E require a split with a BLE peripheral, matching corne.

---

## Scenario → FR / SC traceability

| Scenario | Covers |
|----------|--------|
| A | SC-001; FR-G1, G2, C1, C2, C4; US1 scenarios 1, 2, 3 |
| B | SC-002; FR-C6; US1 scenario 2 |
| C | FR-C5; US1 scenario 3; research.md §R1.3 (10 s TTL known approximation) |
| D | SC-003; FR-B3; US2 scenario 2 |
| E | FR-B5; US2 scenario 3 |
| F | SC-005; US3 scenarios 1, 2, 3 |
| G | SC-004; FR-G1; US1 scenario 4 |

Scenarios **not** scripted here (implementation-time only):
- SC-006 (binary size delta ≤ 4 KB) — measured by `west build --target=print_zephyr_image_size` on each build in Scenario F; one-time check at tag time.
- SC-007 (zero regression on `swift test` + `pytest conformance/tests/`) — run from the main keybeacon repo; neither suite depends on firmware internals, so this reduces to "both suites still green at feature-001 branch head" (already true at the start of this feature).
