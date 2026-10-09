# Copyright (c) 2026 KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# User Story 1 (T026): pure-function unit tests for host_state + profile field
# validation in conformance_tool.check_us1_fields. All tests feed raw bytes to
# parse_connectivity and inspect the resulting field_support + C8 sub-check
# accumulator without any BLE I/O.
#
# Scope (per tasks.md T026): bit combinations, out-of-range index, all-zero
# bytes, reserved bits non-zero, profile_open decoding, C8 finalisation
# precedence.

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from conformance_tool import (  # noqa: E402
    Report,
    _finalise_c8,
    check_us1_fields,
    default_field_support,
    parse_connectivity,
)


def _make_payload(
    cap_byte: int = 0x06,
    host_byte: int = 0x01,
    profile_idx_byte: int = 0x01,
    profile_max: int = 5,
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


# ---------------------------------------------------------------------------
# Pure parser: host_state bit decoding
# ---------------------------------------------------------------------------


def test_parse_host_state_connected_unknown_reason():
    parsed = parse_connectivity(_make_payload(host_byte=0x01))
    assert parsed["host_state"]["connected"] is True
    assert parsed["host_state"]["last_disconnect_reason"] == 0
    assert parsed["host_state"]["reserved_bits_3_7"] == 0


def test_parse_host_state_disconnected_explicit():
    # byte 0b00000010 → connected=False, reason=1 (explicit)
    parsed = parse_connectivity(_make_payload(host_byte=0x02))
    assert parsed["host_state"]["connected"] is False
    assert parsed["host_state"]["last_disconnect_reason"] == 1


def test_parse_host_state_timeout_reason():
    # byte 0b00000100 → connected=False, reason=2 (timeout)
    parsed = parse_connectivity(_make_payload(host_byte=0x04))
    assert parsed["host_state"]["connected"] is False
    assert parsed["host_state"]["last_disconnect_reason"] == 2


def test_parse_host_state_reserved_bits_non_zero():
    # byte 0b11111001 → connected=True, reason=0, reserved=0b11111
    parsed = parse_connectivity(_make_payload(host_byte=0xF9))
    assert parsed["host_state"]["connected"] is True
    assert parsed["host_state"]["last_disconnect_reason"] == 0
    assert parsed["host_state"]["reserved_bits_3_7"] == 0x1F


# ---------------------------------------------------------------------------
# Pure parser: profile byte decoding
# ---------------------------------------------------------------------------


def test_parse_profile_open_bit_true():
    # byte 0x82 → is_open=True, index=0x02
    parsed = parse_connectivity(_make_payload(profile_idx_byte=0x82, profile_max=5))
    assert parsed["profile"]["index"] == 2
    assert parsed["profile"]["is_open"] is True
    assert parsed["profile"]["max_slots"] == 5


def test_parse_profile_open_bit_false():
    parsed = parse_connectivity(_make_payload(profile_idx_byte=0x03, profile_max=5))
    assert parsed["profile"]["index"] == 3
    assert parsed["profile"]["is_open"] is False


def test_parse_profile_zero_bytes():
    parsed = parse_connectivity(_make_payload(profile_idx_byte=0x00, profile_max=0))
    assert parsed["profile"]["index"] == 0
    assert parsed["profile"]["is_open"] is False
    assert parsed["profile"]["max_slots"] == 0


# ---------------------------------------------------------------------------
# check_us1_fields: host_connection
# ---------------------------------------------------------------------------


def test_host_connection_unsupported_when_capability_zero():
    parsed = parse_connectivity(_make_payload(cap_byte=0x00, host_byte=0x01))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["host_connection"] == "unsupported"
    assert "host_state" not in extras.get("c8_evaluations", {})


def test_host_connection_supported_when_reserved_zero():
    # cap 0x02 → has_host_connection=1; host_byte 0x01 → connected, reserved=0
    parsed = parse_connectivity(_make_payload(cap_byte=0x02, host_byte=0x01))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["host_connection"] == "supported"
    assert extras["c8_evaluations"]["host_state"]["status"] == "PASS"


def test_host_connection_warn_when_reserved_nonzero():
    # cap 0x02 → has_host_connection=1; host_byte 0xF9 → reserved=0x1F
    parsed = parse_connectivity(_make_payload(cap_byte=0x02, host_byte=0xF9))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["host_connection"] == "malformed"
    sub = extras["c8_evaluations"]["host_state"]
    assert sub["status"] == "WARN"
    assert "reserved bits 3-7 non-zero" in sub["detail"]


def test_host_connection_warn_single_reserved_bit():
    # host_byte 0b00001001 → connected=True, reason=0, reserved=0b00001
    parsed = parse_connectivity(_make_payload(cap_byte=0x02, host_byte=0x09))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["host_connection"] == "malformed"
    assert extras["c8_evaluations"]["host_state"]["status"] == "WARN"


# ---------------------------------------------------------------------------
# check_us1_fields: profile
# ---------------------------------------------------------------------------


def test_profile_unsupported_when_capability_zero():
    # cap 0x00 → has_profile=0
    parsed = parse_connectivity(_make_payload(cap_byte=0x00, profile_idx_byte=0x02, profile_max=5))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["profile"] == "unsupported"
    assert "profile" not in extras.get("c8_evaluations", {})


def test_profile_supported_within_range():
    # cap 0x04 → has_profile=1; profile_idx 0x03, max 0x05 → OK
    parsed = parse_connectivity(_make_payload(cap_byte=0x04, profile_idx_byte=0x03, profile_max=5))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["profile"] == "supported"
    assert extras["c8_evaluations"]["profile"]["status"] == "PASS"


def test_profile_boundary_index_equals_max_slots():
    parsed = parse_connectivity(_make_payload(cap_byte=0x04, profile_idx_byte=0x05, profile_max=5))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["profile"] == "supported"


def test_profile_fail_when_index_exceeds_max():
    # cap 0x04 → has_profile=1; profile_idx 0x06, max 0x05 → FAIL
    parsed = parse_connectivity(_make_payload(cap_byte=0x04, profile_idx_byte=0x06, profile_max=5))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["profile"] == "malformed"
    sub = extras["c8_evaluations"]["profile"]
    assert sub["status"] == "FAIL"
    assert "6" in sub["detail"] and "5" in sub["detail"]


def test_profile_fail_when_max_slots_zero_but_has_profile():
    parsed = parse_connectivity(_make_payload(cap_byte=0x04, profile_idx_byte=0x00, profile_max=0))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["profile"] == "malformed"
    assert extras["c8_evaluations"]["profile"]["status"] == "FAIL"


def test_profile_open_bit_does_not_affect_validation():
    # cap 0x04; profile byte 0x81 → index=1, is_open=1; max=5 → still PASS
    parsed = parse_connectivity(_make_payload(cap_byte=0x04, profile_idx_byte=0x81, profile_max=5))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["profile"] == "supported"
    assert parsed["profile"]["is_open"] is True


# ---------------------------------------------------------------------------
# C8 finalisation precedence (FAIL > WARN > PASS > SKIP)
# ---------------------------------------------------------------------------


def test_c8_finalise_fail_beats_warn():
    report = Report(use_color=False)
    extras = {
        "c8_evaluations": {
            "host_state": {"status": "WARN", "detail": "reserved bits"},
            "profile": {"status": "FAIL", "detail": "idx > max"},
        }
    }
    _finalise_c8(extras, report)
    assert report.results["C8"].status == "FAIL"
    assert "idx > max" in report.results["C8"].detail


def test_c8_finalise_warn_beats_pass():
    report = Report(use_color=False)
    extras = {
        "c8_evaluations": {
            "host_state": {"status": "WARN", "detail": "reserved bits"},
            "profile": {"status": "PASS", "detail": None},
        }
    }
    _finalise_c8(extras, report)
    assert report.results["C8"].status == "WARN"


def test_c8_finalise_all_pass():
    report = Report(use_color=False)
    extras = {
        "c8_evaluations": {
            "host_state": {"status": "PASS", "detail": None},
            "profile": {"status": "PASS", "detail": None},
        }
    }
    _finalise_c8(extras, report)
    assert report.results["C8"].status == "PASS"


def test_c8_finalise_skip_when_empty():
    report = Report(use_color=False)
    extras = {}
    _finalise_c8(extras, report)
    assert report.results["C8"].status == "SKIP"
    assert report.results["C8"].detail == "not evaluated"


# ---------------------------------------------------------------------------
# End-to-end: both fields unsupported → C8 stays SKIP
# ---------------------------------------------------------------------------


def test_both_fields_unsupported_leaves_c8_skip():
    parsed = parse_connectivity(_make_payload(cap_byte=0x00))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    report = Report(use_color=False)
    _finalise_c8(extras, report)
    assert extras["field_support"]["host_connection"] == "unsupported"
    assert extras["field_support"]["profile"] == "unsupported"
    assert report.results["C8"].status == "SKIP"


# ---------------------------------------------------------------------------
# All-zero payload → both unsupported, no FAIL
# ---------------------------------------------------------------------------


def test_all_zero_payload_renders_cleanly():
    parsed = parse_connectivity(bytes(7))
    extras = _fresh_extras()
    check_us1_fields(parsed, extras)
    assert extras["field_support"]["host_connection"] == "unsupported"
    assert extras["field_support"]["profile"] == "unsupported"
    assert "c8_evaluations" not in extras or extras["c8_evaluations"] == {}
