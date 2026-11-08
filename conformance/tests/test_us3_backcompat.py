# Copyright (c) 2026 KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# US3 (T036): backward-compatibility vectors for the KBP 1.2 Link-slot
# characteristic. These assert that the two degraded wire scenarios NEVER
# produce a spurious conformance failure:
#
#   1. Old firmware (no AA4): C13/C14 stay SKIP, link_slot = "unsupported",
#      and the overall verdict is unaffected (exit code PASS).
#   2. AA4 present but Connectivity (AA2) absent: C13 still PASS on a valid
#      read-only shape, C14 degrades to WARN (cannot bound the slot without
#      profile_max_slots) — never FAIL. This mirrors the app-side
#      "discovery.anomaly" degradation (AA4 without AA2 → cannot-determine).

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from conformance_tool import (  # noqa: E402
    EXIT_PASS,
    Report,
    check_us5_link_slot,
    default_field_support,
    parse_link_slot,
)


def _run(raw, chars_present, profile_max_slots):
    report = Report(use_color=False)
    extras = {"field_support": default_field_support("1.2")}
    check_us5_link_slot(raw, chars_present, profile_max_slots, extras, report)
    return report, extras


# ---------------------------------------------------------------------------
# Scenario 1: old firmware — AA4 absent → SKIP, unsupported, no failure
# ---------------------------------------------------------------------------


def test_backcompat_old_firmware_no_aa4_skips_without_failure():
    chars = {"AA440AA4": {"present": False}}
    report, extras = _run(None, chars, profile_max_slots=5)

    assert report.results["C13"].status == "SKIP"
    assert report.results["C14"].status == "SKIP"
    assert extras["field_support"]["link_slot"] == "unsupported"
    # A missing optional characteristic must not sink the overall verdict.
    assert report.determine_exit_code() == EXIT_PASS


def test_backcompat_old_firmware_aa1_only_minor_is_not_12():
    # AA1 only (KBP 1.0) — declared MINOR must not claim 1.1/1.2.
    report = Report(use_color=False)
    assert report.determine_declared_minor({"AA440AA1": True}) == "1.0"
    assert report.determine_declared_minor({}) == "unknown"


# ---------------------------------------------------------------------------
# Scenario 2: AA4 present but AA2 absent → C13 PASS, C14 WARN (never FAIL)
# ---------------------------------------------------------------------------


def test_backcompat_aa4_without_aa2_warns_not_fails():
    chars = {"AA440AA4": {"present": True, "properties": ["read"], "ccc": False}}
    # profile_max_slots is None because the Connectivity characteristic (AA2)
    # was never discovered — the host surfaces this as discovery.anomaly.
    report, extras = _run(bytes([0x03]), chars, profile_max_slots=None)

    assert report.results["C13"].status == "PASS"
    assert report.results["C14"].status == "WARN"
    assert "AA2" in report.results["C14"].detail
    # WARN is advisory; the overall verdict still conforms.
    assert report.determine_exit_code() == EXIT_PASS


def test_backcompat_aa4_without_aa2_slot_zero_is_pass():
    # slot = 0 (not determined) is always valid, even with no AA2 to bound it.
    chars = {"AA440AA4": {"present": True, "properties": ["read"], "ccc": False}}
    report, _ = _run(bytes([0x00]), chars, profile_max_slots=None)

    assert report.results["C13"].status == "PASS"
    assert report.results["C14"].status == "PASS"
    assert report.determine_exit_code() == EXIT_PASS


def test_backcompat_aa4_without_aa2_parse_still_sound():
    # The parser is independent of AA2 presence.
    parsed = parse_link_slot(bytes([0x02]))
    assert parsed is not None
    assert parsed["slot"] == 2
    assert parsed["not_determined"] is False
