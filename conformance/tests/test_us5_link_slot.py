# Copyright (c) 2026 KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# KBP 1.2 / User Story 5: pure-function unit tests for the Link-slot
# characteristic (AA440AA4-…). Exercises both the `parse_link_slot` payload
# parser and the `check_us5_link_slot` C13/C14 classifier without any BLE I/O,
# per the project constitution (Testing & Verification Discipline): "payload-
# parsing and classification logic MUST be covered by pure-function unit tests
# runnable without BLE hardware" and spec FR-014 (wire→state mapping exhausted).
#
# Scope (tasks.md T009): exhaustive slot = 0 / 1..max, bit 7 ignored for the
# slot value, empty payload → None, and out-of-range (slot > profile_max_slots)
# detection.

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from conformance_tool import (  # noqa: E402
    Report,
    check_us5_link_slot,
    default_field_support,
    parse_link_slot,
)


# ---------------------------------------------------------------------------
# parse_link_slot — happy path + slot masking
# ---------------------------------------------------------------------------


def test_parse_link_slot_not_determined_zero():
    got = parse_link_slot(bytes([0x00]))
    assert got == {
        "raw": 0x00,
        "slot": 0,
        "not_determined": True,
        "reserved_bit7": False,
        "trailing_bytes_ignored": 0,
    }


def test_parse_link_slot_one_based_slot():
    got = parse_link_slot(bytes([0x01]))
    assert got is not None
    assert got["slot"] == 1
    assert got["not_determined"] is False
    assert got["reserved_bit7"] is False


def test_parse_link_slot_exhaustive_0_to_127():
    """Every 7-bit slot value parses to itself with bit 7 clear."""
    for slot in range(0, 128):
        got = parse_link_slot(bytes([slot]))
        assert got is not None
        assert got["slot"] == slot
        assert got["reserved_bit7"] is False
        assert got["not_determined"] is (slot == 0)


# ---------------------------------------------------------------------------
# parse_link_slot — bit 7 (reserved) is recorded but ignored for the slot
# ---------------------------------------------------------------------------


def test_parse_link_slot_bit7_ignored_for_slot_value():
    """bit 7 set MUST NOT bleed into the slot; it is recorded for diagnostics."""
    for slot in range(0, 128):
        byte0 = slot | 0x80
        got = parse_link_slot(bytes([byte0]))
        assert got is not None
        assert got["slot"] == slot  # bit 7 masked off
        assert got["reserved_bit7"] is True
        assert got["raw"] == byte0


# ---------------------------------------------------------------------------
# parse_link_slot — trailing bytes / empty / wrong type
# ---------------------------------------------------------------------------


def test_parse_link_slot_trailing_bytes_ignored():
    got = parse_link_slot(bytes([0x02, 0xAA, 0xBB, 0xCC]))
    assert got is not None
    assert got["slot"] == 2
    assert got["trailing_bytes_ignored"] == 3


def test_parse_link_slot_empty_returns_none():
    assert parse_link_slot(b"") is None
    assert parse_link_slot(bytes(0)) is None


def test_parse_link_slot_wrong_type_returns_none():
    assert parse_link_slot(None) is None  # type: ignore[arg-type]
    assert parse_link_slot("0") is None  # type: ignore[arg-type]
    assert parse_link_slot([0]) is None  # type: ignore[arg-type]


def test_parse_link_slot_bytearray_input_accepted():
    got = parse_link_slot(bytearray([0x05]))
    assert got is not None
    assert got["slot"] == 5


# ---------------------------------------------------------------------------
# check_us5_link_slot — helpers
# ---------------------------------------------------------------------------


def _char_info(present=True, properties=("read",), ccc=False):
    return {
        "AA440AA4": {
            "present": present,
            "properties": list(properties),
            "ccc": ccc,
        }
    }


def _run_check(raw, chars_present, profile_max_slots):
    report = Report(use_color=False)
    extras = {"field_support": default_field_support("1.2")}
    check_us5_link_slot(raw, chars_present, profile_max_slots, extras, report)
    return report, extras


# ---------------------------------------------------------------------------
# check_us5_link_slot — absent characteristic → SKIP / unsupported
# ---------------------------------------------------------------------------


def test_check_absent_leaves_c13_c14_skip_and_unsupported():
    report, extras = _run_check(None, _char_info(present=False), profile_max_slots=5)
    assert report.results["C13"].status == "SKIP"
    assert report.results["C14"].status == "SKIP"
    assert extras["field_support"]["link_slot"] == "unsupported"


# ---------------------------------------------------------------------------
# check_us5_link_slot — C13 happy path (read-only, no CCC) + C14 within range
# ---------------------------------------------------------------------------


def test_check_happy_read_only_within_range():
    report, extras = _run_check(bytes([0x02]), _char_info(), profile_max_slots=5)
    assert report.results["C13"].status == "PASS"
    assert report.results["C14"].status == "PASS"
    assert extras["field_support"]["link_slot"] == "supported"
    assert extras["link_slot_parsed"]["slot"] == 2


def test_check_slot_zero_is_pass_not_determined():
    report, extras = _run_check(bytes([0x00]), _char_info(), profile_max_slots=5)
    assert report.results["C13"].status == "PASS"
    assert report.results["C14"].status == "PASS"
    assert "not determined" in report.results["C14"].detail


def test_check_slot_equal_to_max_is_pass():
    report, _ = _run_check(bytes([0x05]), _char_info(), profile_max_slots=5)
    assert report.results["C14"].status == "PASS"


def test_check_exhaustive_slots_within_range_pass():
    """slot = 1..max all pass C14 when bounded by profile_max_slots."""
    max_slots = 8
    for slot in range(1, max_slots + 1):
        report, _ = _run_check(bytes([slot]), _char_info(), profile_max_slots=max_slots)
        assert report.results["C13"].status == "PASS", f"slot={slot}"
        assert report.results["C14"].status == "PASS", f"slot={slot}"


# ---------------------------------------------------------------------------
# check_us5_link_slot — C13 FAIL cases (property / payload violations)
# ---------------------------------------------------------------------------


def test_check_c13_fail_when_notify_advertised():
    report, extras = _run_check(
        bytes([0x01]), _char_info(properties=("read", "notify")), profile_max_slots=5
    )
    assert report.results["C13"].status == "FAIL"
    assert "READ-only" in report.results["C13"].detail
    assert extras["field_support"]["link_slot"] == "malformed"


def test_check_c13_fail_when_ccc_present():
    report, _ = _run_check(bytes([0x01]), _char_info(ccc=True), profile_max_slots=5)
    assert report.results["C13"].status == "FAIL"
    assert "CCC" in report.results["C13"].detail


def test_check_c13_fail_when_read_missing():
    report, _ = _run_check(
        bytes([0x01]), _char_info(properties=("indicate",)), profile_max_slots=5
    )
    assert report.results["C13"].status == "FAIL"


def test_check_c13_fail_when_no_data():
    report, _ = _run_check(None, _char_info(), profile_max_slots=5)
    assert report.results["C13"].status == "FAIL"
    assert "no data" in report.results["C13"].detail
    # C14 cannot range-check a missing payload.
    assert report.results["C14"].status == "SKIP"


def test_check_c13_fail_when_empty_payload():
    report, _ = _run_check(b"", _char_info(), profile_max_slots=5)
    assert report.results["C13"].status == "FAIL"
    assert "shorter than 1 byte" in report.results["C13"].detail
    assert report.results["C14"].status == "SKIP"


def test_check_c13_fail_when_reserved_bit7_set():
    """bit 7 set is a C13 violation; the slot itself (C14) is still checked."""
    report, _ = _run_check(bytes([0x83]), _char_info(), profile_max_slots=5)
    assert report.results["C13"].status == "FAIL"
    assert "bit 7" in report.results["C13"].detail
    # slot = 0x83 & 0x7F = 3, within [1, 5] → C14 PASS
    assert report.results["C14"].status == "PASS"


# ---------------------------------------------------------------------------
# check_us5_link_slot — C14 out-of-range + unbounded (no AA2) cases
# ---------------------------------------------------------------------------


def test_check_c14_fail_when_slot_exceeds_max():
    report, extras = _run_check(bytes([0x06]), _char_info(), profile_max_slots=5)
    assert report.results["C13"].status == "PASS"
    assert report.results["C14"].status == "FAIL"
    assert "profile_max_slots" in report.results["C14"].detail
    assert extras["field_support"]["link_slot"] == "malformed"


def test_check_c14_warn_when_no_connectivity():
    """A non-zero slot with no AA2 cannot be bounded → WARN, not FAIL."""
    report, _ = _run_check(bytes([0x03]), _char_info(), profile_max_slots=None)
    assert report.results["C13"].status == "PASS"
    assert report.results["C14"].status == "WARN"


def test_check_c14_slot_zero_pass_even_without_connectivity():
    report, _ = _run_check(bytes([0x00]), _char_info(), profile_max_slots=None)
    assert report.results["C14"].status == "PASS"
