# Copyright (c) 2026 KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# User Story 4: pure-function unit tests for charging_flags validation in
# conformance_tool.check_us4_charging. Not an explicit tasks.md task (US4 only
# has the hardware-dependent T040), but required by the project constitution
# (Testing & Verification Discipline): "payload-parsing and classification
# logic MUST be covered by pure-function unit tests runnable without BLE
# hardware".

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from conformance_tool import (  # noqa: E402
    check_us4_charging,
    default_field_support,
    parse_connectivity,
)


def _make_payload(cap_byte: int = 0x20, charging_byte: int = 0x00) -> bytes:
    return bytes([cap_byte, 0x00, 0x00, 0x00, 0x00, 0x00, charging_byte])


def _fresh_extras() -> dict:
    return {"field_support": default_field_support("1.1")}


# ---------------------------------------------------------------------------
# capability bit = 0 → unsupported
# ---------------------------------------------------------------------------


def test_charging_unsupported_when_both_caps_zero():
    # cap 0x00: no has_left_charging / has_right_charging
    parsed = parse_connectivity(_make_payload(cap_byte=0x00, charging_byte=0x00))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    assert extras["field_support"]["left_charging"] == "unsupported"
    assert extras["field_support"]["right_charging"] == "unsupported"
    assert "charging_flags" not in extras.get("c8_evaluations", {})


# ---------------------------------------------------------------------------
# P-C5: has_right_charging without is_split → FAIL
# ---------------------------------------------------------------------------


def test_charging_fail_when_has_right_without_is_split():
    # cap 0x40: has_right_charging=1, is_split=0 → P-C5 FAIL
    parsed = parse_connectivity(_make_payload(cap_byte=0x40, charging_byte=0x02))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    sub = extras["c8_evaluations"]["charging_flags"]
    assert sub["status"] == "FAIL"
    assert "P-C5" in sub["detail"]
    assert extras["field_support"]["right_charging"] == "malformed"


# ---------------------------------------------------------------------------
# Normal cases (both halves supported)
# ---------------------------------------------------------------------------


def test_charging_pass_when_both_supported_and_zero():
    # cap 0x61: is_split=1, has_left_charging=1, has_right_charging=1; charging byte 0x00
    parsed = parse_connectivity(_make_payload(cap_byte=0x61, charging_byte=0x00))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    assert extras["field_support"]["left_charging"] == "supported"
    assert extras["field_support"]["right_charging"] == "supported"
    assert extras["c8_evaluations"]["charging_flags"]["status"] == "PASS"


def test_charging_pass_when_left_charging_only():
    # cap 0x21: is_split=1, has_left_charging=1, has_right_charging=0; charging byte 0x01
    parsed = parse_connectivity(_make_payload(cap_byte=0x21, charging_byte=0x01))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    assert extras["field_support"]["left_charging"] == "supported"
    assert extras["field_support"]["right_charging"] == "unsupported"
    assert extras["c8_evaluations"]["charging_flags"]["status"] == "PASS"


def test_charging_pass_when_both_sides_charging_true():
    # cap 0x61 (both supported, is_split=1); charging byte 0x03 (both charging)
    parsed = parse_connectivity(_make_payload(cap_byte=0x61, charging_byte=0x03))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    assert extras["field_support"]["left_charging"] == "supported"
    assert extras["field_support"]["right_charging"] == "supported"
    assert extras["c8_evaluations"]["charging_flags"]["status"] == "PASS"


# ---------------------------------------------------------------------------
# WARN: bit set without capability
# ---------------------------------------------------------------------------


def test_charging_warn_when_bit_zero_set_without_left_capability():
    # cap 0x00: both unsupported; byte 0x01 → bit 0 set
    parsed = parse_connectivity(_make_payload(cap_byte=0x00, charging_byte=0x01))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    sub = extras["c8_evaluations"]["charging_flags"]
    assert sub["status"] == "WARN"
    assert "has_left_charging = 0" in sub["detail"]


def test_charging_warn_when_bit_one_set_without_right_capability():
    # cap 0x21: is_split=1, has_left_charging=1, has_right_charging=0; byte 0x02
    parsed = parse_connectivity(_make_payload(cap_byte=0x21, charging_byte=0x02))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    sub = extras["c8_evaluations"]["charging_flags"]
    assert sub["status"] == "WARN"
    assert "has_right_charging = 0" in sub["detail"]


def test_charging_warn_when_reserved_bits_nonzero():
    # cap 0x21; byte 0xFC → bits 2-7 all set, 0-1 all zero
    parsed = parse_connectivity(_make_payload(cap_byte=0x21, charging_byte=0xFC))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    sub = extras["c8_evaluations"]["charging_flags"]
    assert sub["status"] == "WARN"
    assert "reserved bits 2-7 non-zero" in sub["detail"]


# ---------------------------------------------------------------------------
# FAIL beats WARN: has_right_charging=1 && is_split=0 && bit 1 set
# ---------------------------------------------------------------------------


def test_charging_fail_takes_precedence_over_warn():
    # cap 0x40: has_right_charging=1, is_split=0; byte 0x02 → bit 1 set
    parsed = parse_connectivity(_make_payload(cap_byte=0x40, charging_byte=0x02))
    extras = _fresh_extras()
    check_us4_charging(parsed, extras)
    sub = extras["c8_evaluations"]["charging_flags"]
    assert sub["status"] == "FAIL"
    assert "P-C5" in sub["detail"]
