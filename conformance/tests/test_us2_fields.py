# Copyright (c) 2026 KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# User Story 2 (T032): pure-function unit tests for split_link + Battery field
# validation in conformance_tool.check_us2_split_link and check_us2_battery.
# All tests feed raw bytes without any BLE I/O.
#
# Scope (per tasks.md T032): is_split combinations, Battery length mismatch,
# sentinel 255 single-side, 101-254 reserved values, P-C1 violations.

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from conformance_tool import (  # noqa: E402
    Report,
    check_us2_battery,
    check_us2_split_link,
    default_field_support,
    parse_connectivity,
)


def _make_payload(
    cap_byte: int = 0x00,
    host_byte: int = 0x00,
    profile_idx_byte: int = 0x00,
    profile_max: int = 0,
    split_byte: int = 0x00,
    endpoint_byte: int = 0x00,
    charging_byte: int = 0x00,
) -> bytes:
    return bytes(
        [
            cap_byte,
            host_byte,
            profile_idx_byte,
            profile_max,
            split_byte,
            endpoint_byte,
            charging_byte,
        ]
    )


def _fresh_extras() -> dict:
    return {"field_support": default_field_support("1.1")}


def _chars(aa3_present: bool = True) -> dict:
    return {
        "AA440AA3": {"present": aa3_present, "properties": [], "ccc": False},
    }


# ---------------------------------------------------------------------------
# check_us2_split_link
# ---------------------------------------------------------------------------


def test_split_link_unsupported_when_capability_zero():
    # cap byte 0x00: has_split_link = 0
    parsed = parse_connectivity(_make_payload(cap_byte=0x00, split_byte=0x03))
    extras = _fresh_extras()
    check_us2_split_link(parsed, extras)
    assert extras["field_support"]["split_link"] == "unsupported"
    assert "split_link" not in extras.get("c8_evaluations", {})


def test_split_link_fail_when_has_split_link_without_is_split():
    # cap byte 0x08: has_split_link=1, is_split=0 → P-C1 FAIL
    parsed = parse_connectivity(_make_payload(cap_byte=0x08, split_byte=0x03))
    extras = _fresh_extras()
    check_us2_split_link(parsed, extras)
    assert extras["field_support"]["split_link"] == "malformed"
    sub = extras["c8_evaluations"]["split_link"]
    assert sub["status"] == "FAIL"
    assert "P-C1" in sub["detail"]


def test_split_link_supported_when_both_online():
    # cap 0x09: is_split=1 + has_split_link=1; split byte 0x03: both online
    parsed = parse_connectivity(_make_payload(cap_byte=0x09, split_byte=0x03))
    extras = _fresh_extras()
    check_us2_split_link(parsed, extras)
    assert extras["field_support"]["split_link"] == "supported"
    assert extras["c8_evaluations"]["split_link"]["status"] == "PASS"


def test_split_link_supported_when_right_offline():
    # cap 0x09; split byte 0x01: left online, right offline (still valid)
    parsed = parse_connectivity(_make_payload(cap_byte=0x09, split_byte=0x01))
    extras = _fresh_extras()
    check_us2_split_link(parsed, extras)
    assert extras["field_support"]["split_link"] == "supported"


def test_split_link_warn_when_reserved_bits_nonzero():
    # cap 0x09; split byte 0xFF: both online + reserved=0b111111
    parsed = parse_connectivity(_make_payload(cap_byte=0x09, split_byte=0xFF))
    extras = _fresh_extras()
    check_us2_split_link(parsed, extras)
    assert extras["field_support"]["split_link"] == "malformed"
    sub = extras["c8_evaluations"]["split_link"]
    assert sub["status"] == "WARN"
    assert "reserved bits 2-7 non-zero" in sub["detail"]


# ---------------------------------------------------------------------------
# check_us2_battery — characteristic absent
# ---------------------------------------------------------------------------


def test_battery_characteristic_absent_leaves_c9_skip():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(None, is_split=False, chars_present=_chars(aa3_present=False),
                      extras=extras, report=report)
    assert report.results["C9"].status == "SKIP"
    assert extras["field_support"]["overall_battery"] == "unsupported"
    assert extras["field_support"]["left_battery"] == "unsupported"
    assert extras["field_support"]["right_battery"] == "unsupported"


# ---------------------------------------------------------------------------
# check_us2_battery — overall (is_split=False)
# ---------------------------------------------------------------------------


def test_battery_overall_normal_pass():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([72]), is_split=False, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "PASS"
    assert extras["field_support"]["overall_battery"] == "supported"
    assert extras["field_support"]["left_battery"] == "unsupported"
    assert extras["field_support"]["right_battery"] == "unsupported"


def test_battery_overall_sentinel_pass():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([0xFF]), is_split=False, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "PASS"
    assert extras["field_support"]["overall_battery"] == "supported"


def test_battery_overall_reserved_value_warn():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([150]), is_split=False, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "WARN"
    assert "0x96" in report.results["C9"].detail
    assert extras["field_support"]["overall_battery"] == "malformed"


def test_battery_overall_length_mismatch_fail():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([50, 60]), is_split=False, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "FAIL"
    assert "length 2 != 1" in report.results["C9"].detail
    assert extras["field_support"]["overall_battery"] == "malformed"


def test_battery_overall_empty_payload_fail():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(b"", is_split=False, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "FAIL"


# ---------------------------------------------------------------------------
# check_us2_battery — split (is_split=True)
# ---------------------------------------------------------------------------


def test_battery_split_normal_pass():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([80, 75]), is_split=True, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "PASS"
    assert extras["field_support"]["left_battery"] == "supported"
    assert extras["field_support"]["right_battery"] == "supported"
    assert extras["field_support"]["overall_battery"] == "unsupported"


def test_battery_split_one_sentinel_pass():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([0xFF, 60]), is_split=True, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "PASS"
    assert extras["field_support"]["left_battery"] == "supported"
    assert extras["field_support"]["right_battery"] == "supported"


def test_battery_split_one_reserved_value_warn():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([110, 55]), is_split=True, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "WARN"
    assert "left_battery" in report.results["C9"].detail
    assert extras["field_support"]["left_battery"] == "malformed"
    assert extras["field_support"]["right_battery"] == "supported"


def test_battery_split_both_reserved_warn():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([200, 150]), is_split=True, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "WARN"
    detail = report.results["C9"].detail
    assert "left_battery" in detail and "right_battery" in detail
    assert extras["field_support"]["left_battery"] == "malformed"
    assert extras["field_support"]["right_battery"] == "malformed"


def test_battery_split_length_mismatch_fail():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([50]), is_split=True, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "FAIL"
    assert "length 1 != 2" in report.results["C9"].detail
    assert extras["field_support"]["left_battery"] == "malformed"
    assert extras["field_support"]["right_battery"] == "malformed"


def test_battery_split_boundary_hundred_percent():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([100, 100]), is_split=True, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "PASS"


def test_battery_split_boundary_zero_percent():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([0, 0]), is_split=True, chars_present=_chars(),
                      extras=extras, report=report)
    assert report.results["C9"].status == "PASS"


def test_battery_parsed_stashed_in_extras():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(bytes([33, 44]), is_split=True, chars_present=_chars(),
                      extras=extras, report=report)
    assert "battery_parsed" in extras
    assert extras["battery_parsed"]["left"]["percent"] == 33
    assert extras["battery_parsed"]["right"]["percent"] == 44


def test_battery_present_but_raw_none_fail():
    report = Report(use_color=False)
    extras = _fresh_extras()
    check_us2_battery(None, is_split=False, chars_present=_chars(aa3_present=True),
                      extras=extras, report=report)
    assert report.results["C9"].status == "FAIL"
    assert "returned no data" in report.results["C9"].detail
