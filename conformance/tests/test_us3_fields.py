# Copyright (c) 2026 KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# User Story 3 (T036): pure-function unit tests for output_endpoint field
# validation in conformance_tool.check_us3_output_endpoint.
#
# Scope (per tasks.md T036): output_endpoint byte 0/1/2/3/255 mapping and
# reserved-value warning.

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from conformance_tool import (  # noqa: E402
    check_us3_output_endpoint,
    default_field_support,
    parse_connectivity,
)


def _make_payload(cap_byte: int = 0x10, endpoint_byte: int = 0x00) -> bytes:
    return bytes([cap_byte, 0x00, 0x00, 0x00, 0x00, endpoint_byte, 0x00])


def _fresh_extras() -> dict:
    return {"field_support": default_field_support("1.1")}


def test_output_endpoint_unsupported_when_capability_zero():
    parsed = parse_connectivity(_make_payload(cap_byte=0x00, endpoint_byte=0x01))
    extras = _fresh_extras()
    check_us3_output_endpoint(parsed, extras)
    assert extras["field_support"]["output_endpoint"] == "unsupported"
    assert "output_endpoint" not in extras.get("c8_evaluations", {})


def test_output_endpoint_unknown_code_pass():
    parsed = parse_connectivity(_make_payload(cap_byte=0x10, endpoint_byte=0x00))
    extras = _fresh_extras()
    check_us3_output_endpoint(parsed, extras)
    assert extras["field_support"]["output_endpoint"] == "supported"
    assert extras["c8_evaluations"]["output_endpoint"]["status"] == "PASS"


def test_output_endpoint_usb_pass():
    parsed = parse_connectivity(_make_payload(cap_byte=0x10, endpoint_byte=0x01))
    extras = _fresh_extras()
    check_us3_output_endpoint(parsed, extras)
    assert extras["field_support"]["output_endpoint"] == "supported"
    assert extras["c8_evaluations"]["output_endpoint"]["status"] == "PASS"


def test_output_endpoint_ble_pass():
    parsed = parse_connectivity(_make_payload(cap_byte=0x10, endpoint_byte=0x02))
    extras = _fresh_extras()
    check_us3_output_endpoint(parsed, extras)
    assert extras["field_support"]["output_endpoint"] == "supported"
    assert extras["c8_evaluations"]["output_endpoint"]["status"] == "PASS"


def test_output_endpoint_reserved_three_warn():
    parsed = parse_connectivity(_make_payload(cap_byte=0x10, endpoint_byte=0x03))
    extras = _fresh_extras()
    check_us3_output_endpoint(parsed, extras)
    assert extras["field_support"]["output_endpoint"] == "malformed"
    sub = extras["c8_evaluations"]["output_endpoint"]
    assert sub["status"] == "WARN"
    assert "0x03" in sub["detail"]


def test_output_endpoint_reserved_255_warn():
    parsed = parse_connectivity(_make_payload(cap_byte=0x10, endpoint_byte=0xFF))
    extras = _fresh_extras()
    check_us3_output_endpoint(parsed, extras)
    assert extras["field_support"]["output_endpoint"] == "malformed"
    sub = extras["c8_evaluations"]["output_endpoint"]
    assert sub["status"] == "WARN"
    assert "0xFF" in sub["detail"]


def test_output_endpoint_reserved_warn_does_not_fail():
    parsed = parse_connectivity(_make_payload(cap_byte=0x10, endpoint_byte=0x7F))
    extras = _fresh_extras()
    check_us3_output_endpoint(parsed, extras)
    sub = extras["c8_evaluations"]["output_endpoint"]
    assert sub["status"] == "WARN"
    assert sub["status"] != "FAIL"
