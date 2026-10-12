# PR body draft — zmk-keybeacon feat/compat-contract-v1.1.4 → main

> This file is the staging ground for the merge PR body. When ready to open the
> PR on github.com, copy-paste this content. Lives in the main `keybeacon` repo
> because the module repo doesn't carry Spec Kit artefacts.

---

## Summary

Introduces the **ZMK revision compatibility contract** to `zmk-keybeacon` and
ships it as **v1.1.4**. Fixes the 002-era compile failure against newer ZMK
revisions (post-commit [`6e7e0de2`][zmk-6e7e0de2], 2026-02-12) *and* builds a
module-side guardrail so future ZMK API drift fails fast at CMake configure
time with a readable banner instead of a cryptic C error.

[zmk-6e7e0de2]: https://github.com/zmkfirmware/zmk/commit/6e7e0de2

**No wire-protocol change.** Every KBP 1.1 byte, UUID, and Kconfig default
is bit-for-bit identical with v1.1.3.

## Why this matters

A user's CI run ([ykiewang/zmk-config-totem#38043117244][ci-run]) failed with:

```
keybeacon.c:243:39: warning: implicit declaration of function 'zmk_endpoints_selected';
                              did you mean 'zmk_endpoint_get_selected'?
keybeacon.c:243:39: error: invalid initializer
```

Root cause: ZMK upstream renamed the API in commit `6e7e0de2`. v1.1.3 compiles
on older ZMK but not newer; the only workaround was to disable Connectivity
in `.conf` — silently removing a host-side feature.

This release makes **both ZMK revisions** compile cleanly and gives the
maintainer tooling to catch the next upstream break within 24 hours.

[ci-run]: https://github.com/ykiewang/zmk-config-totem/actions/runs/38043117244

## What's in it

Three independent user stories, each independently testable:

| | US | Deliverable | Independent test |
|---|---|---|---|
| 🎯 MVP | **US1** (P1) | `#ifdef` double-API bridge in `keybeacon.c:243`; CMake probe + fail-fast banner; Kconfig escape hatch | smoke-cmake.sh (4 sections) + 12 pytest cases |
| | **US2** (P2) | Daily `zmk-main-compat.yml` **symbol-probe** matrix (`main` + `4dd95d7…` + `e844eca2…`); auto-opened issue on cron break (`compat-break` label) | regen_ci.py --check; drill via validate_compat |
| | **US3** (P2) | Auto-generated README Compatibility table; CHANGELOG v1.1.4; 002 upgrade notes | update-readme-table.py --check |

Total: 24 pytest cases + 1 shell smoke script, all green locally and on CI.

**US2 scope clarification.** The matrix verifies ZMK API **symbol stability**
by running `check_zmk_compat.py` against each pinned ZMK clone — fast,
board-agnostic, exactly the semantics the fail-fast banner is built around.
It does **not** attempt a full end-to-end `west build` for a specific
board/shield combination; that is the consuming `zmk-config` repo's job and
the split-keyboard ecosystem is too fragmented to pick a canonical shield
inside this module repo. See the `pivot(003)[ci]:` commit for the full
rationale.

## Files

```
compatibility.yaml                               NEW (single source of truth)
compatibility.schema.yaml                        NEW (JSON Schema for the above)
Kconfig.keybeacon                                MOD (+ CONFIG_ZMK_KEYBEACON_ALLOW_INCOMPATIBLE_ZMK)
keybeacon.cmake                                  MOD (+ include(cmake/zmk_compat.cmake))
keybeacon.c                                      MOD (keybeacon.c:243 #ifdef bridge)
cmake/zmk_compat.cmake                           NEW (CMake-side probe entry)
scripts/check_zmk_compat.py                      NEW (symbol probe + banner)
scripts/validate_compat.py                       NEW (L1/L2/L3 manifest gate)
scripts/regen_ci.py                              NEW (workflow yaml generator)
scripts/update-readme-table.py                   NEW (README table generator)
scripts/one-time-setup.sh                        NEW (gh label create)
scripts/requirements-dev.txt                     NEW
scripts/tests/{__init__,conftest}.py             NEW
scripts/tests/test_{check,validate,regen,update}_*.py  NEW (23 cases)
scripts/tests/fixtures/{manifest-*.yaml, zmk-*/, expected_banner_v1.1.4.txt}  NEW
scripts/tests/smoke-cmake.sh                     NEW
.github/workflows/zmk-main-compat.yml            NEW (derived from compatibility.yaml)
.pre-commit-config.yaml                          NEW (optional)
README.md                                        MOD (+ badge, + Compatibility table)
CHANGELOG.md                                     MOD (+ v1.1.4 entry)
```

## Constitution Check

Per Principle V, every PR touching normative artefacts must include this check.
Full table in [plan.md Post-Design Constitution Re-Check][plan-ccr]:

[plan-ccr]: https://github.com/ykiewang/keybeacon/blob/main/specs/003-zmk-revision-pinning/plan.md

| Principle | Status | Note |
|---|---|---|
| I. Wire-Contract Self-Containment | ✅ | zero `protocol/` or `conformance/` edits; v1.1.4 wire is byte-identical to v1.1.3 |
| II. Backward Compatibility | ✅ | PATCH release; `default n` for the new Kconfig keeps old behaviour |
| III. Identity From Protocol | ⚪ N/A | host-side feature; not relevant here |
| IV. Observable Degradation | ✅ (reinforced) | fail-fast banner is "hidden over invented" at build time |
| V. Spec-First | ✅ | full workflow: specify → plan → tasks → implement; artefacts in `specs/003-zmk-revision-pinning/` |
| VI. Bilingual Normative Docs | ✅ (routed) | spec/plan Chinese; `../zmk-keybeacon/README.md` English-primary (not in Principle VI scope); upgrade-notes.md bilingual |

No Complexity Tracking entries required.

## Also

The branch `fix/endpoint-get-selected` on this repo (commit `608a4d2`) was a
pre-003 exploratory attempt. It solved only half of the problem (would compile
on newer ZMK but break older ZMK) and is **not merged**; kept as an
investigation record. See spec Clarifications § Session 2026-10-12 for the
full reasoning trail.

**Upstream branch state note.** When starting feature 003 the repo's `main`
HEAD was `6c15918`, which is two commits behind the `v1.1.3` tag (`cbfe34f`):
the v1.1.3 release was tagged on a chain (`6c15918 → e4dc6a5 → cbfe34f`) that
never got fast-forwarded back to `main`. `feat/compat-contract-v1.1.4` was
branched off **`v1.1.3`** rather than `main`, so merging this PR will
simultaneously bring `main` up to v1.1.3 **and** add v1.1.4 — no separate
catch-up PR is needed. Reviewers can confirm with
`git log main..v1.1.3 --oneline` (2 commits) and `git log v1.1.3..main`
(empty).

## Testing

- Local: `pytest scripts/tests/` → 23 passed
- Local: `scripts/tests/smoke-cmake.sh` → all 4 sections pass
- CI: the matrix added by this PR runs **on this PR itself** via the
  `pull_request` trigger. First-time `compat-break` label creation:
  `gh label create compat-break --color d73a4a` (recorded in
  `scripts/one-time-setup.sh`).

## Follow-up (post-merge)

- Tag `v1.1.4` after this merges; `scripts/update-readme-table.py` then
  replaces the "`v1.1.4 — pending (via --pending-tag)`" row with the real
  tag at the next release.
- Hardware validation on Totem keyboard: see
  `specs/003-zmk-revision-pinning/manual-run-log.md` (T039 / T040 / T056).
