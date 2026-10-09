# Implementation Plan: zmk-keybeacon module — KBP 1.1 Connectivity & Power

**Branch**: `feat/kbp-1.1-connectivity-power` (in sibling `zmk-keybeacon` repo) | **Date**: 2026-10-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-zmk-keybeacon-kbp11/spec.md`

**Note**: Spec Kit lives in this `keybeacon` repo but the implementation surface is the sibling repo at `/Users/wangyuting19/kbd/keybeacon/zmk-keybeacon/`. The Spec Kit tracked branch here (`002-zmk-keybeacon-kbp11`) is a bookkeeping branch for spec/plan/tasks; the actual firmware source branch is `feat/kbp-1.1-connectivity-power` in `../zmk-keybeacon/`.

## Summary

Add KBP 1.1 Connectivity (`AA440AA2-…`) and Battery (`AA440AA3-…`) characteristics to the existing `zmk-keybeacon` Zephyr module while keeping the KBP 1.0 characteristic `AA440AA1-…` byte-for-byte unchanged. Two new Kconfig sub-options (`ZMK_KEYBEACON_CONNECTIVITY`, `ZMK_KEYBEACON_BATTERY`) gate the new characteristics; both `default y` under `CONFIG_ZMK_KEYBEACON=y` so the typical corne-class consumer upgrades `west.yml revision: v1.0.0 → v1.1.0` and gets the new fields with zero `.conf` change. Charger-GPIO support is deferred: `has_left_charging`/`has_right_charging` capability bits default `0` and firmware emits `0` for `charging_flags.bit 0/1` on all boards in this release. All code changes land in the sibling `zmk-keybeacon` repo; `../zmk-config-corne/` is not touched this feature.

**Technical approach**: single C file (`keybeacon.c`) grows to host three characteristics; three independent emit paths (layer/mods on `AA1`, connectivity snapshot on `AA2`, battery snapshot on `AA3`); each has its own cache + change-detect + snapshot-unchanged suppression. Connectivity is fed by four ZMK event subscriptions (`zmk_ble_active_profile_changed`, `zmk_split_bt_peripheral_status_changed`, `zmk_endpoint_changed`, plus the existing layer/mods events whose state is irrelevant to AA2); Battery is fed by two subscriptions (`zmk_battery_state_changed`, `zmk_peripheral_battery_state_changed`) plus a 1 Hz work queue to satisfy the ≥ 1 s floor of §14.4.5's OR relation. Compile-time `BUILD_ASSERT`s guard payload length against protocol drift; `#if defined`-guards degrade gracefully when an event hook is unavailable on an older ZMK (FR-K3). Verification: live `conformance_tool.py` on the user's Corne for SC-001/SC-002, bytes diff of `AA1` payload between v1.0.0 and v1.1.0 for FR-G1/SC-004, GATT discovery comparison for SC-005.

## Technical Context

**Language/Version**: C (Zephyr-flavored, C11 effective per Zephyr toolchain); Kconfig; CMake for module integration.

**Primary Dependencies**:

- Zephyr RTOS (whatever version `zmkfirmware/zmk@6b44d33` targets — Zephyr 3.5 era based on the June 2025 commit date).
- ZMK core APIs (public ones listed in `protocol/README.md §14.8`); concrete header paths resolved in `research.md`.
- No new runtime dependencies, no new Zephyr subsystems, no new Kconfig trees added by this feature (reuses `CONFIG_ZMK_BLE`, `CONFIG_ZMK_SPLIT`, `CONFIG_ZMK_SPLIT_ROLE_CENTRAL`, `CONFIG_ZMK_BATTERY_REPORTING` where present).

**Storage**: N/A (firmware; all state is RAM-cached payload buffers inside the module, no persistent store).

**Testing**:

- Firmware-level: no in-tree unit tests shipped by this module today (v1.0.0 has none, and Zephyr module authors conventionally test by consumer-side probe). This feature preserves that approach — rationale captured under Constitution Check / Testing Discipline.
- Byte-level parsing + classification is covered externally by `conformance/tests/*.py` (81 pytest cases, pure-function, already green at feature-001 branch head). These exercise the same payload layouts this module produces, giving effective parse-side coverage without duplication.
- Build-time: `BUILD_ASSERT` for payload-length / struct-size invariants (static assertion, no test harness needed).
- End-to-end: live Corne hardware probed by the cross-platform `conformance_tool.py` on the main keybeacon repo — procedure captured in Phase 1 `quickstart.md`.

**Target Platform**:

- Reference central MCUs: `nice_nano_v2` (NRF52840) and `puchi_ble_v1` (NRF52840) per `../zmk-config-corne/build.yaml` — matches the user's actual hardware.
- Any Zephyr-supported ZMK central qualifies; this module makes no board-specific assumptions beyond `CONFIG_ZMK_SPLIT_ROLE_CENTRAL`.

**Project Type**: Zephyr module (library-flavoured — `zephyr_library()` emits a single translation unit linked into the consumer firmware image).

**Performance Goals**:

- Payload build cost ≤ 50 µs per rebuild on NRF52840 at the ZMK 64 MHz core clock (connectivity payload is 7 bytes with a handful of API reads; well within any realistic budget).
- NOTIFY throttling MUST satisfy §14.4.5 (≥ 1 pp OR ≥ 1 s for battery); SC-003 bounds this at ≤ 60 NOTIFY / 60 s.

**Constraints**:

- **≤ 4 KB text-section growth** vs v1.0.0 build (SC-006) — binary budget is tight on NRF52840 split builds already running displays + Studio.
- **Zero RAM beyond ~70 bytes** per added characteristic (7-byte payload buf + 7-byte cache + CCC bookkeeping; ~16 bytes for battery). No dynamic allocation.
- Must not alter the `AA440AA1-…` characteristic value, its emission cadence, or its CCC behaviour (FR-G1 / SC-004).
- Must inherit the existing `CONFIG_ZMK_SPLIT_ROLE_CENTRAL` gate (FR-G2) so the module never links into peripheral or `settings_reset` images.

**Scale/Scope**:

- Module LOC: ~100 (v1.0.0) → ~380 (v1.1.0) estimate. One file: `keybeacon.c`. Two docs touched: `README.md`, `CHANGELOG.md`. Kconfig gains two lines.
- Supported consumer count: unlimited (semver-tagged module; this feature is a MINOR tag).
- Verification scope: 1 reference board family (Corne central/peripheral on nice_nano_v2 + puchi_ble_v1), 3 Kconfig combinations (v1.0.0, v1.1.0 both-on, v1.1.0 both-off), 1 KBP 1.0 host regression, 1 KBP 1.1 host end-to-end.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md v1.0.0` (6 principles + Platform Scope + Testing Discipline + Governance).

### Principle I — Wire-Contract Self-Containment: **PASS**

- The feature's wire behaviour is **entirely** read from `protocol/README.md §14.3/14.4/14.5/14.7/14.8` (keybeacon main repo) and `conformance/CONFORMANCE.md §8` (same repo).
- The module reproduces those byte offsets / UUIDs / event names verbatim; **no new wire fields are invented** by this plan.
- `zmk-keybeacon` is **not** in `app/*/` nor `conformance/*/`, so Principle I's cross-dir dependency rules do not apply. The module is a third-party conforming producer that could be read out and re-implemented by anyone from `protocol/README.md` alone (demonstrating the principle's leverage).

### Principle II — Backward Compatibility is Non-Negotiable: **PASS**

- Delivers a MINOR tag `v1.1.0` on an existing `v1.0.0` module. Service UUID unchanged. `AA440AA1-…` byte-identical (FR-G1).
- Two **new optional** characteristics appended; KBP §9 MINOR rule exactly ("adding a new optional characteristic/descriptor. Service UUID unchanged").
- SC-004 is the behavioural regression gate (KBP 1.0 host sees zero change).
- No existing REQUIRED conformance item is weakened; C1–C6 continue to pass.

### Principle III — Identity From Protocol, Not Branding: **PASS**

- The module is keyboard-independent (`README.md` L13: "The shared logic in `keybeacon.c` is never modified to port the feature"). This feature preserves that: no board matcher, no GAP-name parsing, no vendor hook.
- `capability_bits` is computed **structurally** from Kconfig / `IS_ENABLED(...)` symbols — i.e. from what the firmware was configured to produce, not from "is this an X-brand board".

### Principle IV — Observable Degradation Over Guessing: **PASS**

- `has_left_charging` / `has_right_charging` default to `0` → consumers hide the field entirely (correct behaviour, enforced by host-side spec `001-connectivity-power` FR-005 and C8).
- Battery `255` sentinel is used for "unavailable" rather than a fake `0` (FR-B2, FR-B5) — the firmware-side correlate of the host-side 3 s staleness rule.
- `#if defined`-guards for optional ZMK events (FR-K3) emit `0` on the field and keep the capability bit `0`, consistent with "render nothing" for missing data.
- `BUILD_ASSERT`s catch field drift (which would otherwise be a silent lie) at compile time.

### Principle V — Spec-First Development (NON-NEGOTIABLE): **PASS (scoped as voluntary adherence)**

- Principle V's listed scope is `protocol/`, `conformance/`, `app/*/Sources/`. The sibling `zmk-keybeacon` repo is **not** in that list, so a feature-dir is not strictly required.
- However the main `001-connectivity-power` feature-dir already captured the host + protocol work; this plan is the firmware-counterpart artefact and ships through the same Spec Kit workflow voluntarily for traceability. **This is extra discipline, not a violation.**

### Principle VI — Bilingual Normative Docs: **PASS**

- `zmk-keybeacon/README.md` and `CHANGELOG.md` are **not** in Principle VI's listed scope, but the existing README is already bilingual (English + 中文). FR-D1/FR-D2 preserve the mirror discipline for the v1.1.0 additions.
- `conformance/CONFORMANCE.md §8` (the normative keyboard-author guide) is already bilingual on `main` — this feature does not touch it (host-side `001-connectivity-power` already covered the §8 bilingual mirror).

### Platform Scope & Delivery: **PASS**

- Firmware reference is ZMK — exactly matches this feature. The module places ZMK API hooks under `#if defined`-guards (FR-K3), reflecting the Platform Scope note "API hooks are non-normative examples; conformance is judged solely at the wire."

### Testing & Verification Discipline: **PASS (with documented substitution)**

- Firmware component: Zephyr-module convention in this project is to **not** ship in-tree unit tests (v1.0.0 ships none). This feature maintains that status quo.
- **Substitution**: byte-level parsing + classification coverage is delivered via the existing `conformance/tests/*.py` suite (81 pytest cases on `main`) which already exercises the same payload layouts this module produces (parse side ≡ emit-side's dual). This satisfies "Payload-parsing and classification logic MUST be covered by pure-function unit tests runnable without BLE hardware" at the project level — the test suite is in `conformance/`, not in `zmk-keybeacon/`, which is appropriate because `conformance/` is the project's cross-stack verification home.
- `BUILD_ASSERT`s give static (compile-time) coverage for payload length and struct layout.
- End-to-end: quickstart.md will ship with Given/When/Then scenarios mapped to FR / SC IDs (feature's spec already lists them).
- Reference keyboard: Corne (the user's actual hardware; Totem is historical reference per the constitution's `## Platform Scope`). This is noted in quickstart.md.
- Regression gate: SC-004 + SC-007 (zero regressions on existing XCTest + pytest suites).

### Governance: **PASS**

- Compliance Review: this `plan.md` is the required Constitution Check artefact. Will be re-evaluated post Phase 1 design.

**Verdict**: all 6 principles + 3 process gates PASS; **no Complexity Tracking entries required**.

## Project Structure

### Documentation (this feature)

```text
specs/002-zmk-keybeacon-kbp11/
├── spec.md                 # /speckit-specify output (23 KB; 3 priorities + 23 FR + 7 SC)
├── plan.md                 # This file (/speckit-plan command output)
├── research.md             # Phase 0 output (/speckit-plan command)
├── data-model.md           # Phase 1 output (/speckit-plan command)
├── quickstart.md           # Phase 1 output (/speckit-plan command)
├── contracts/              # Phase 1 output (/speckit-plan command)
│   ├── connectivity-characteristic.md  # AA440AA2-… 7-byte payload contract
│   ├── battery-characteristic.md       # AA440AA3-… 1/2-byte payload contract
│   └── kconfig-interface.md            # ZMK_KEYBEACON_CONNECTIVITY / _BATTERY contract
├── checklists/
│   └── requirements.md     # 15/15 pass (from /speckit-specify)
└── tasks.md                # /speckit-tasks output (NOT created by this command)
```

### Source Code (sibling repository: `../zmk-keybeacon/`)

```text
../zmk-keybeacon/            # separate git repo, branch feat/kbp-1.1-connectivity-power
├── CMakeLists.txt           # unchanged (delegates to keybeacon.cmake)
├── keybeacon.cmake          # unchanged (central-only guard already covers 1.1)
├── Kconfig.keybeacon        # +2 symbols: ZMK_KEYBEACON_CONNECTIVITY, _BATTERY (both default y)
├── keybeacon.c              # grows ~100 → ~380 LOC
│                            #   - keeps AA1 service entry + build_payload() + update_and_notify() byte-identical
│                            #   - adds AA2 service entry + conn_build_payload() + conn_update_and_notify()
│                            #   - adds AA3 service entry + batt_build_payload() + batt_update_and_notify()
│                            #   - adds 6 ZMK_SUBSCRIPTIONs (profile / split / endpoint / battery × 2 / existing layer+keycode)
│                            #   - adds 1 Hz k_work_delayable for battery OR-throttling floor
│                            #   - all three characteristics live in one BT_GATT_SERVICE_DEFINE
├── zephyr/
│   └── module.yml           # unchanged
├── README.md                # bump KBP 1.0.0 → KBP 1.1.0 + "What's new in 1.1" bilingual block
└── CHANGELOG.md             # add ## [1.1.0] — 2026-10-09 entry
```

**Structure Decision**: single-file `keybeacon.c` module stays single-file. Separating the three characteristics into three `.c` files would (a) break the "move the module as one include()" promise of `keybeacon.cmake`, (b) add compile-time symbol duplication for the shared `BT_GATT_SERVICE_DEFINE`, and (c) make byte-identical-prefix verification for FR-G1 harder (git diff is cleanest with the old prefix left untouched in the same file). Internal structure uses static helpers prefixed with `conn_` / `batt_` to keep concerns clearly separated inside one translation unit. Rationale aligns with Principle I (self-containment) at the module level: a third party reading `keybeacon.c` sees the full 1.1 producer in one place.

**Target repo isolation**: no file under `/Users/wangyuting19/kbd/keybeacon/keybeacon/` is modified by this feature (except these spec/plan artefacts under `specs/002-…/`). All source changes are relative to `../zmk-keybeacon/`.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| *(none)* | — | — |

Constitution Check passed on all 6 principles + 3 process gates without justification; no complexity to track.

---

## Post-Phase 1 Constitution Re-Check

Re-evaluated after `research.md` + `data-model.md` + `contracts/{connectivity,battery,kconfig-interface}.md` + `quickstart.md` were produced.

### Principle I — Wire-Contract Self-Containment: **STILL PASS**

- Phase 1 added no new wire fields. Every byte position in `contracts/connectivity-characteristic.md §2` and `contracts/battery-characteristic.md §2` is a verbatim mirror of `protocol/README.md §14.3.1 / §14.4.1`.
- The contracts explicitly flag themselves as "mirror" artefacts (not source of truth): e.g. connectivity-characteristic.md L5 "This contract **mirrors** that normative text; where any conflict arises, protocol §14.3 wins."

### Principle II — Backward Compatibility: **STILL PASS**

- Data-model §E5 locks in the attribute-index strategy that preserves `&keybeacon_svc.attrs[1]` for AA1 NOTIFY (unchanged from v1.0.0), and uses `attrs[4]` / `attrs[7]` for the new characteristics — AA1's attribute identity survives verbatim.
- Kconfig contract §3 gives an explicit "byte-indistinguishable" guarantee for the opt-out combination, codified as SC-005 and Scenario F in quickstart.md.
- Scenario G (quickstart.md) is the KBP 1.0 host regression gate, directly validating FR-G1.

### Principle III — Identity From Protocol, Not Branding: **STILL PASS**

- Nothing in Phase 1 added a vendor hook, board matcher, or name-based gate.
- `capability_bits` is **compile-time** from Kconfig (data-model.md §E4), not runtime-detected from board strings.

### Principle IV — Observable Degradation Over Guessing: **STILL PASS and strengthened**

- Research.md §R1.3 (10 s TTL for `right_online`) and §R1.5 (charger GPIO deferred to v1.2) are both honest-degradation choices: capability bits for unsupported fields stay `0` and the host hides the field entirely.
- Battery sentinel `255` for "unavailable" (contracts/battery §2, §6) is the firmware correlate of host-side staleness rendering (`001-connectivity-power` C-B3).
- No "0%", "unknown", or placeholder values anywhere in the design.

### Principle V — Spec-First Development: **STILL PASS**

- All five artefacts specified by the Spec Kit flow (spec, plan, research, data-model, contracts, quickstart) are present and cross-referenced. No code has been written in the sibling `zmk-keybeacon` repo yet.
- `/speckit-tasks` is the next command; `/speckit-implement` is strictly after.

### Principle VI — Bilingual Normative Docs: **STILL PASS**

- Phase 1 artefacts are in-scope "non-normative feature specs" per Principle VI, which may be English-only (they are). The *module's* normative docs (`zmk-keybeacon/README.md` + `CHANGELOG.md`) get the bilingual mirror update in Phase 2's implementation per FR-D1 + FR-D2.

### Platform Scope & Delivery: **STILL PASS**

- Research.md §R4 implements the `#if defined` + `IS_ENABLED` guards reflecting "API hooks are non-normative examples; conformance is judged solely at the wire."

### Testing & Verification Discipline: **STILL PASS**

- Pure-function parsing coverage: existing `conformance/tests/*.py` (81 pytest cases, unchanged by this feature) tests the same byte layouts this module produces — the parse/emit sides are dual, so emit-side correctness is observable through parse-side tests. No new tests required by this feature on either side.
- Compile-time coverage: `BUILD_ASSERT`s in data-model §E1 and §E3 catch payload-length drift.
- End-to-end: quickstart.md Scenarios A–G map explicitly to FR / SC IDs (last table in that file).
- Reference keyboard: Corne (user's hardware); noted in quickstart.md "Reference-keyboard note" paragraph.
- Regression: SC-004 (Scenario G) and SC-007 are the regression gates.

### Governance / Compliance Review: **STILL PASS**

- This plan.md re-check is itself the Compliance Review artefact. **No violations.** No Complexity Tracking entries needed.

**Post-Phase 1 verdict**: all 6 principles + 3 process gates still PASS; no new complexity introduced by Phase 1 design; ready for `/speckit-tasks`.
