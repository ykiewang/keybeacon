# Copyright (c) 2026 KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# Pure-function unit tests for conformance_tool.py's payload parsers.
# These tests exercise `parse_connectivity` and `parse_battery` without any
# BLE I/O, matching the Testing & Verification Discipline requirement in the
# project constitution: "Payload-parsing and classification logic MUST be
# covered by pure-function unit tests runnable without BLE hardware."
#
# Scope (per tasks.md T010): happy path, short payload (< 7 bytes), long
# payload (> 7 bytes), reserved-bit tolerance. Field-level semantic tests
# (per-user-story) live in test_us1_fields.py / test_us2_fields.py etc.

from __future__ import annotations

import sys
from pathlib import Path

# Allow importing the sibling conformance_tool.py without an installed package.
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from conformance_tool import parse_battery, parse_connectivity  # noqa: E402


# ---------------------------------------------------------------------------
# parse_connectivity — happy path
# ---------------------------------------------------------------------------


def test_parse_connectivity_happy_minimal_7_bytes():
    """A 7-byte payload with all zero bits is a valid 'nothing supported' snapshot."""
    data = bytes([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    got = parse_connectivity(data)
    assert got is not None
    assert got["capability_bits"]["raw"] == 0x00
    assert got["capability_bits"]["is_split"] is False
    assert got["capability_bits"]["has_host_connection"] is False
    assert got["host_state"]["connected"] is False
    assert got["profile"]["index"] == 0
    assert got["profile"]["is_open"] is False
    assert got["profile"]["max_slots"] == 0
    assert got["split_link"]["left_online"] is False
    assert got["split_link"]["right_online"] is False
    assert got["output_endpoint"]["code"] == 0
    assert got["charging_flags"]["left_charging"] is False
    assert got["charging_flags"]["right_charging"] is False
    assert got["trailing_bytes_ignored"] == 0


def test_parse_connectivity_all_fields_populated():
    """Realistic snapshot: split keyboard with everything live."""
    # capability_bits: is_split | has_host_connection | has_profile | has_split_link
    #                | has_output_endpoint | has_left_charging | has_right_charging = 0x7F
    # host_state:  connected=1 + reason=0 (unknown)                     = 0x01
    # profile_index: 2 (0b010), profile_open=1 (bit 7)                   = 0x82
    # profile_max_slots: 5                                               = 0x05
    # split_link: left=1, right=1                                        = 0x03
    # output_endpoint: BLE (2)                                           = 0x02
    # charging_flags: left_charging=1, right_charging=1                  = 0x03
    data = bytes([0x7F, 0x01, 0x82, 0x05, 0x03, 0x02, 0x03])
    got = parse_connectivity(data)
    assert got is not None
    bits = got["capability_bits"]
    assert bits["is_split"] is True
    assert bits["has_host_connection"] is True
    assert bits["has_profile"] is True
    assert bits["has_split_link"] is True
    assert bits["has_output_endpoint"] is True
    assert bits["has_left_charging"] is True
    assert bits["has_right_charging"] is True
    assert bits["reserved_bit7"] is False
    assert got["host_state"]["connected"] is True
    assert got["host_state"]["last_disconnect_reason"] == 0
    assert got["profile"]["index"] == 2
    assert got["profile"]["is_open"] is True
    assert got["profile"]["max_slots"] == 5
    assert got["split_link"]["left_online"] is True
    assert got["split_link"]["right_online"] is True
    assert got["output_endpoint"]["code"] == 2
    assert got["charging_flags"]["left_charging"] is True
    assert got["charging_flags"]["right_charging"] is True


# ---------------------------------------------------------------------------
# parse_connectivity — short / long / malformed input
# ---------------------------------------------------------------------------


def test_parse_connectivity_short_6_bytes_returns_none():
    """Payload < 7 bytes MUST be rejected (invariant C-C1)."""
    assert parse_connectivity(bytes(6)) is None
    assert parse_connectivity(bytes(0)) is None
    assert parse_connectivity(b"") is None


def test_parse_connectivity_long_12_bytes_ignores_tail():
    """Payload > 7 bytes: parse bytes 0..6, record trailing count (invariant C-C2)."""
    head = bytes([0x01, 0x01, 0x81, 0x05, 0x01, 0x01, 0x01])
    tail = bytes([0xAA, 0xBB, 0xCC, 0xDD, 0xEE])
    got = parse_connectivity(head + tail)
    assert got is not None
    assert got["trailing_bytes_ignored"] == 5
    # The parsed values come only from the first 7 bytes.
    assert got["capability_bits"]["is_split"] is True
    assert got["profile"]["is_open"] is True
    assert got["output_endpoint"]["code"] == 0x01


def test_parse_connectivity_wrong_type_returns_none():
    assert parse_connectivity(None) is None  # type: ignore[arg-type]
    assert parse_connectivity("0" * 7) is None  # type: ignore[arg-type]
    assert parse_connectivity([0] * 7) is None  # type: ignore[arg-type]


def test_parse_connectivity_bytearray_input_accepted():
    """bytearray is a valid input type (same as bytes)."""
    data = bytearray([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    assert parse_connectivity(data) is not None


# ---------------------------------------------------------------------------
# parse_connectivity — reserved-bit tolerance
# ---------------------------------------------------------------------------


def test_parse_connectivity_reserved_bit7_tolerated():
    """Setting capability_bits bit 7 (reserved) does not break parsing.

    This is the forward-compatibility knob (invariant IV-C2): a future KBP
    1.2 firmware may set bit 7 to signal a new field; today's host MUST
    simply record it and keep going.
    """
    data = bytes([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    got = parse_connectivity(data)
    assert got is not None
    assert got["capability_bits"]["reserved_bit7"] is True
    # Known bits remain zero.
    assert got["capability_bits"]["is_split"] is False


def test_parse_connectivity_host_state_reserved_bits_recorded():
    """host_state bits 3-7 should be reserved and emitted-as-0 by 1.1 firmware,
    but if a firmware bug sets them, the parser MUST still return a value and
    simply record them for diagnostics."""
    # 0b11111001 -> connected=1, reason=0 (bits 1-2 = 00), bits 3-7 = 0b11111 = 31
    data = bytes([0x00, 0b11111001, 0x00, 0x00, 0x00, 0x00, 0x00])
    got = parse_connectivity(data)
    assert got is not None
    assert got["host_state"]["connected"] is True
    assert got["host_state"]["last_disconnect_reason"] == 0
    assert got["host_state"]["reserved_bits_3_7"] == 0x1F


def test_parse_connectivity_split_link_reserved_bits_tolerated():
    """split_link_flags bits 2-7 reserved; non-zero values are tolerated."""
    # bit 0 and 1 set + bits 2-7 all set -> 0xFF
    data = bytes([0x08, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00])
    got = parse_connectivity(data)
    assert got is not None
    assert got["split_link"]["left_online"] is True
    assert got["split_link"]["right_online"] is True
    assert got["split_link"]["reserved_bits_2_7"] == 0x3F


def test_parse_connectivity_charging_flags_reserved_bits_tolerated():
    """charging_flags bits 2-7 reserved; parser MUST not reject them."""
    data = bytes([0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
    got = parse_connectivity(data)
    assert got is not None
    assert got["charging_flags"]["left_charging"] is True
    assert got["charging_flags"]["right_charging"] is True
    assert got["charging_flags"]["reserved_bits_2_7"] == 0x3F


# ---------------------------------------------------------------------------
# parse_battery — happy path (overall)
# ---------------------------------------------------------------------------


def test_parse_battery_overall_normal_percent():
    got = parse_battery(bytes([72]), is_split=False)
    assert got == {
        "is_split": False,
        "overall": {"raw": 72, "state": "percent", "percent": 72},
    }


def test_parse_battery_overall_sentinel_255():
    got = parse_battery(bytes([255]), is_split=False)
    assert got is not None
    assert got["overall"] == {"raw": 255, "state": "unavailable"}


def test_parse_battery_overall_reserved_value_flagged():
    """Values 101-254 are reserved; render as unavailable + out_of_range (C-B3)."""
    got = parse_battery(bytes([150]), is_split=False)
    assert got is not None
    assert got["overall"]["state"] == "unavailable"
    assert got["overall"]["out_of_range"] is True
    assert got["overall"]["raw"] == 150


def test_parse_battery_overall_zero_percent():
    got = parse_battery(bytes([0]), is_split=False)
    assert got is not None
    assert got["overall"] == {"raw": 0, "state": "percent", "percent": 0}


def test_parse_battery_overall_hundred_percent():
    got = parse_battery(bytes([100]), is_split=False)
    assert got is not None
    assert got["overall"] == {"raw": 100, "state": "percent", "percent": 100}


# ---------------------------------------------------------------------------
# parse_battery — happy path (split)
# ---------------------------------------------------------------------------


def test_parse_battery_split_both_present():
    got = parse_battery(bytes([80, 65]), is_split=True)
    assert got == {
        "is_split": True,
        "left": {"raw": 80, "state": "percent", "percent": 80},
        "right": {"raw": 65, "state": "percent", "percent": 65},
    }


def test_parse_battery_split_one_sentinel():
    """A sentinel on one side is independent of the other side."""
    got = parse_battery(bytes([255, 72]), is_split=True)
    assert got is not None
    assert got["left"]["state"] == "unavailable"
    assert got["right"] == {"raw": 72, "state": "percent", "percent": 72}


def test_parse_battery_split_mixed_sentinel_and_reserved():
    got = parse_battery(bytes([200, 255]), is_split=True)
    assert got is not None
    assert got["left"]["state"] == "unavailable"
    assert got["left"]["out_of_range"] is True
    assert got["right"]["state"] == "unavailable"
    # 255 is a valid sentinel; it has no out_of_range flag.
    assert "out_of_range" not in got["right"]


# ---------------------------------------------------------------------------
# parse_battery — length mismatches (C-B1 / C-B2)
# ---------------------------------------------------------------------------


def test_parse_battery_overall_length_mismatch_returns_none():
    assert parse_battery(b"", is_split=False) is None
    assert parse_battery(bytes([50, 50]), is_split=False) is None
    assert parse_battery(bytes([1, 2, 3]), is_split=False) is None


def test_parse_battery_split_length_mismatch_returns_none():
    assert parse_battery(b"", is_split=True) is None
    assert parse_battery(bytes([50]), is_split=True) is None
    assert parse_battery(bytes([1, 2, 3]), is_split=True) is None


def test_parse_battery_wrong_type_returns_none():
    assert parse_battery(None, is_split=False) is None  # type: ignore[arg-type]
    assert parse_battery("72", is_split=False) is None  # type: ignore[arg-type]
    assert parse_battery([72], is_split=False) is None  # type: ignore[arg-type]


def test_parse_battery_bytearray_input_accepted():
    data = bytearray([80, 65])
    assert parse_battery(data, is_split=True) is not None
