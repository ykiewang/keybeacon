#!/usr/bin/env python3
# Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# ============================================================================
# KeyBeacon Protocol (KBP) conformance self-test — cross-platform (bleak).
#
# Covers KBP 1.0 (C1-C6) + KBP 1.1 (C7-C12). Runs on macOS 12+, Linux
# (BlueZ 5.56+), and Windows 10+. The macOS-only PyObjC legacy tool at
# conformance/conformance_tool_macos.py is retained for KBP 1.0 regression and
# as a fallback when `bleak` is unavailable.
#
# Exit codes (per contracts/conformance-cli.md section 2):
#   0  all REQUIRED items pass (or skipped as not-applicable)
#   1  a REQUIRED conformance item failed
#   2  environment error (Bluetooth off, no keyboard, timeout, missing deps)
#
# Usage:
#   python3 conformance/conformance_tool.py [--timeout SEC] [--observe SEC]
#                                           [--json] [--device-filter NAME]
#                                           [--no-color] [-h]
#
# For wire details: ../protocol/README.md (KBP 1.0 sections 1-13, KBP 1.1 section 14).
# For user-visible contract: specs/001-connectivity-power/contracts/conformance-cli.md.
# ============================================================================

from __future__ import annotations

import argparse
import asyncio
import json
import os
import platform
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


# -----------------------------------------------------------------------------
# Constants (wire contract: protocol/README.md sections 1 & 14)
# -----------------------------------------------------------------------------

SERVICE_UUID = "aa440aa0-f5ed-4c48-84a1-8062d20d3d55"
CHAR_STATUS_UUID = "aa440aa1-f5ed-4c48-84a1-8062d20d3d55"       # KBP 1.0
CHAR_CONNECTIVITY_UUID = "aa440aa2-f5ed-4c48-84a1-8062d20d3d55"  # KBP 1.1
CHAR_BATTERY_UUID = "aa440aa3-f5ed-4c48-84a1-8062d20d3d55"       # KBP 1.1
CCC_DESCRIPTOR_UUID = "00002902-0000-1000-8000-00805f9b34fb"
HID_SERVICE_UUID = "00001812-0000-1000-8000-00805f9b34fb"

TOOL_VERSION = "1.1.0"
TOOL_NAME = "conformance_tool.py"
JSON_SPEC_VERSION = "kbp-conformance-cli/1"

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_ENV = 2


# -----------------------------------------------------------------------------
# Pure-function payload parsers (no BLE I/O; unit-testable in pytest).
# -----------------------------------------------------------------------------


def parse_connectivity(data: bytes) -> dict[str, Any] | None:
    """Parse a KBP 1.1 Connectivity characteristic payload.

    Returns a dict of parsed fields, or None if the payload is shorter than
    7 bytes (invariant C-C1). Bytes beyond index 6 are ignored (invariant
    C-C2, MINOR forward-compatibility).

    Field layout matches contracts/protocol-kbp11.md section 3.1 and
    protocol/README.md section 14.3.1.
    """
    if not isinstance(data, (bytes, bytearray)) or len(data) < 7:
        return None

    byte0 = data[0]
    byte1 = data[1]
    byte2 = data[2]
    byte3 = data[3]
    byte4 = data[4]
    byte5 = data[5]
    byte6 = data[6]

    capability_bits = {
        "raw": byte0,
        "is_split": bool(byte0 & 0x01),
        "has_host_connection": bool(byte0 & 0x02),
        "has_profile": bool(byte0 & 0x04),
        "has_split_link": bool(byte0 & 0x08),
        "has_output_endpoint": bool(byte0 & 0x10),
        "has_left_charging": bool(byte0 & 0x20),
        "has_right_charging": bool(byte0 & 0x40),
        "reserved_bit7": bool(byte0 & 0x80),
    }
    host_state = {
        "raw": byte1,
        "connected": bool(byte1 & 0x01),
        "last_disconnect_reason": (byte1 >> 1) & 0x03,
        "reserved_bits_3_7": (byte1 >> 3) & 0x1F,
    }
    profile = {
        "raw_index": byte2,
        "index": byte2 & 0x7F,
        "is_open": bool(byte2 & 0x80),
        "max_slots": byte3,
    }
    split_link = {
        "raw": byte4,
        "left_online": bool(byte4 & 0x01),
        "right_online": bool(byte4 & 0x02),
        "reserved_bits_2_7": (byte4 >> 2) & 0x3F,
    }
    output_endpoint = {
        "raw": byte5,
        # 0 unknown / 1 USB / 2 BLE / 3-255 reserved
        "code": byte5,
    }
    charging_flags = {
        "raw": byte6,
        "left_charging": bool(byte6 & 0x01),
        "right_charging": bool(byte6 & 0x02),
        "reserved_bits_2_7": (byte6 >> 2) & 0x3F,
    }
    trailing = len(data) - 7
    return {
        "capability_bits": capability_bits,
        "host_state": host_state,
        "profile": profile,
        "split_link": split_link,
        "output_endpoint": output_endpoint,
        "charging_flags": charging_flags,
        "trailing_bytes_ignored": trailing,
    }


def parse_battery(data: bytes, is_split: bool) -> dict[str, Any] | None:
    """Parse a KBP 1.1 Battery characteristic payload.

    is_split=False requires length 1 (invariant C-B1); is_split=True requires
    length 2 (invariant C-B2). Returns None on length mismatch.

    Field layout: contracts/protocol-kbp11.md section 4.1 /
    protocol/README.md section 14.4.1.
    """
    if not isinstance(data, (bytes, bytearray)):
        return None
    if is_split:
        if len(data) != 2:
            return None
        return {
            "is_split": True,
            "left": _battery_reading(data[0]),
            "right": _battery_reading(data[1]),
        }
    if len(data) != 1:
        return None
    return {
        "is_split": False,
        "overall": _battery_reading(data[0]),
    }


def _battery_reading(byte: int) -> dict[str, Any]:
    if 0 <= byte <= 100:
        return {"raw": byte, "state": "percent", "percent": byte}
    if byte == 255:
        return {"raw": byte, "state": "unavailable"}
    # 101-254 are reserved; render as unavailable + out_of_range flag (C-B3).
    return {"raw": byte, "state": "unavailable", "out_of_range": True}


# -----------------------------------------------------------------------------
# Report model
# -----------------------------------------------------------------------------


@dataclass
class CheckResult:
    item_id: str
    level: str  # REQUIRED | RECOMMENDED | MANUAL | REQUIRED_IF_PRESENT
    description: str
    status: str = "SKIP"  # PASS | FAIL | WARN | SKIP | MANUAL
    detail: str | None = None


# Ordered list of all 12 checks, from protocol/README.md section 10 (KBP 1.0)
# and section 14.7 (KBP 1.1).
CHECKLIST_SPEC: list[CheckResult] = [
    CheckResult(
        item_id="C1",
        level="REQUIRED",
        description="Service AA440AA0-… + characteristic AA440AA1-… (READ+NOTIFY, CCC)",
    ),
    CheckResult(
        item_id="C2",
        level="REQUIRED",
        description="READ returns >= 2 bytes; layer_name is valid UTF-8 or empty",
    ),
    CheckResult(
        item_id="C3",
        level="REQUIRED",
        description="NOTIFY on change + snapshot-unchanged suppression (zero idle traffic)",
    ),
    CheckResult(
        item_id="C4",
        level="REQUIRED",
        description="Discoverable while connected (connected-peripheral enumeration)",
    ),
    CheckResult(
        item_id="C5",
        level="RECOMMENDED",
        description="Non-empty GAP device name (fallback allowed)",
    ),
    CheckResult(
        item_id="C6",
        level="MANUAL",
        description="Split: feature only on the central (host-link) role",
    ),
    CheckResult(
        item_id="C7",
        level="REQUIRED_IF_PRESENT",
        description="AA440AA2-… Connectivity characteristic: READ+NOTIFY+CCC",
    ),
    CheckResult(
        item_id="C8",
        level="REQUIRED_IF_PRESENT",
        description="Connectivity READ >= 7 bytes; invariants P-C1..P-C5 hold",
    ),
    CheckResult(
        item_id="C9",
        level="REQUIRED_IF_PRESENT",
        description="AA440AA3-… Battery characteristic: READ+NOTIFY+CCC; length matches is_split",
    ),
    CheckResult(
        item_id="C10",
        level="REQUIRED_IF_PRESENT",
        description="Connectivity NOTIFY on state change + snapshot-unchanged suppression",
    ),
    CheckResult(
        item_id="C11",
        level="RECOMMENDED",  # WARN only, per contract section 5
        description="Battery NOTIFY throttling: >= 1pp change OR >= 1s (OR relation)",
    ),
    CheckResult(
        item_id="C12",
        level="MANUAL",
        description="Split: 1.1 characteristics only on the central (host-link) role",
    ),
]


class Report:
    """Collects per-item results and renders human-readable + JSON output."""

    def __init__(self, use_color: bool = True) -> None:
        self.results: dict[str, CheckResult] = {}
        for template in CHECKLIST_SPEC:
            self.results[template.item_id] = CheckResult(
                item_id=template.item_id,
                level=template.level,
                description=template.description,
                status="SKIP",
                detail="not evaluated",
            )
        self.use_color = use_color and sys.stdout.isatty() and os.environ.get("NO_COLOR") is None

    def set(self, item_id: str, status: str, detail: str | None = None) -> None:
        if item_id not in self.results:
            raise KeyError(f"unknown checklist item: {item_id}")
        existing = self.results[item_id]
        existing.status = status
        existing.detail = detail

    def determine_exit_code(self) -> int:
        """Any REQUIRED (or REQUIRED_IF_PRESENT with a non-SKIP FAIL) → 1."""
        for item in self.results.values():
            if item.status == "FAIL":
                if item.level in ("REQUIRED", "REQUIRED_IF_PRESENT"):
                    return EXIT_FAIL
        return EXIT_PASS

    def determine_verdict(self) -> str:
        code = self.determine_exit_code()
        return "conforms" if code == EXIT_PASS else "nonconforms"

    def determine_declared_minor(self, chars_present: dict[str, bool]) -> str:
        """1.1 if the Connectivity char is advertised; 1.0 if only the status char; unknown otherwise."""
        if chars_present.get("AA440AA2"):
            return "1.1"
        if chars_present.get("AA440AA1"):
            return "1.0"
        return "unknown"

    def render_human(self, extras: dict[str, Any]) -> None:
        print("")
        print("==== KBP conformance self-test ====")
        kbd = extras.get("keyboard", {})
        if kbd.get("name"):
            print(f'keyboard: "{kbd["name"]}"  (address: {kbd.get("address", "unknown")})')
        print(f"declared MINOR: {extras.get('declared_minor', 'unknown')}")
        print("")
        for item in self.results.values():
            mark = self._colorize(item.status)
            print(f"{item.item_id:<4} [{mark:^8}]  {item.description}")
            if item.detail and item.status in ("FAIL", "WARN"):
                print(f"        reason: {item.detail}")
            elif item.detail and item.status == "SKIP":
                print(f"        note:   {item.detail}")
        print("")
        verdict = self.determine_verdict()
        if verdict == "conforms":
            print(f'Verdict: CONFORMS to KBP {extras.get("declared_minor", "unknown")} '
                  f'(keyboard: "{kbd.get("name", "unknown")}")')
        else:
            print(f"Verdict: NONCONFORMS (one or more REQUIRED items failed)")

    def _colorize(self, status: str) -> str:
        if not self.use_color:
            return status
        colors = {
            "PASS": "\x1b[32m",   # green
            "FAIL": "\x1b[31m",   # red
            "WARN": "\x1b[33m",   # yellow
            "SKIP": "\x1b[90m",   # grey
            "MANUAL": "\x1b[36m",  # cyan
        }
        reset = "\x1b[0m"
        return f"{colors.get(status, '')}{status}{reset}"

    def to_json(self, extras: dict[str, Any]) -> dict[str, Any]:
        """Emit the support-matrix JSON per contracts/conformance-cli.md section 4.1.

        Top-level keys are stably ordered (ran_at, tool, keyboard, declared_minor,
        characteristics, capability_bits, field_support, checklist, verdict,
        exit_code; spec_version at the very top). Invariants J-1..J-4 hold.
        """
        kbd = extras.get("keyboard", {})
        chars_present = extras.get("characteristics_present", {})
        declared_minor = extras.get("declared_minor", "unknown")
        capability_bits = extras.get("capability_bits")  # None when 1.0 or unknown
        field_support = extras.get("field_support", {})
        exit_code = self.determine_exit_code()
        verdict = (
            "conforms"
            if exit_code == EXIT_PASS
            else ("environment_error" if exit_code == EXIT_ENV else "nonconforms")
        )
        # Characteristics block (J-4: AA ordering).
        characteristics = {}
        for key in ("AA440AA1", "AA440AA2", "AA440AA3"):
            info = chars_present.get(key, {})
            characteristics[key] = {
                "present": bool(info.get("present", False)),
                "properties": list(info.get("properties", [])),
                "ccc": bool(info.get("ccc", False)),
            }
        return {
            "spec_version": JSON_SPEC_VERSION,
            "ran_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "tool": {
                "name": TOOL_NAME,
                "backend": "bleak",
                "version": TOOL_VERSION,
                "platform": platform.platform(),
            },
            "keyboard": {
                "name": kbd.get("name"),
                "address": kbd.get("address"),
                "service_uuid": SERVICE_UUID,
            },
            "declared_minor": declared_minor,
            "characteristics": characteristics,
            # J-3: when declared_minor == "1.0", capability_bits is null.
            "capability_bits": capability_bits if declared_minor == "1.1" else None,
            "field_support": field_support,
            "checklist": [
                {
                    "id": item.item_id,
                    "level": item.level,
                    "status": item.status,
                    "detail": item.detail,
                }
                for item in self.results.values()
            ],
            "verdict": verdict,
            # J-1: exit_code field equals the process exit code.
            "exit_code": exit_code,
        }


# -----------------------------------------------------------------------------
# Default field_support skeleton (filled in by US-phase checks)
# -----------------------------------------------------------------------------


def default_field_support(declared_minor: str) -> dict[str, str]:
    """field_support with all 1.1 fields set to 'skipped' pending US-phase impl.

    Invariant: when declared_minor == '1.0', every 1.1 field remains 'skipped'
    (not 'unsupported'), signalling that this is a 1.0-only keyboard.
    """
    base = {
        "is_split": "skipped",
        "host_connection": "skipped",
        "profile": "skipped",
        "split_link": "skipped",
        "overall_battery": "skipped",
        "left_battery": "skipped",
        "right_battery": "skipped",
        "output_endpoint": "skipped",
        "left_charging": "skipped",
        "right_charging": "skipped",
    }
    return base


# -----------------------------------------------------------------------------
# BLE discovery + checklist runner (bleak)
# -----------------------------------------------------------------------------


async def discover_and_check(args: argparse.Namespace, report: Report) -> dict[str, Any]:
    """Discover a KBP keyboard, run C1-C12 checks against it, and return extras
    (keyboard info + characteristic presence + capability_bits + field_support).

    This Foundational-phase implementation sets up the discovery/connect scaffold
    and leaves per-field checks as SKIP with a 'implemented in user story phases'
    note. The scaffold itself is enough for `--help` + `--json` smoke runs and
    for pytest unit tests to exercise the pure parsers.
    """
    try:
        from bleak import BleakClient, BleakScanner
        from bleak.exc import BleakError
    except ImportError as exc:
        _env_error(
            f"bleak is not installed: {exc}. "
            f"Install with: python3 -m pip install -U -r conformance/requirements.txt"
        )
        return {}

    extras: dict[str, Any] = {
        "keyboard": {},
        "characteristics_present": {},
        "declared_minor": "unknown",
        "field_support": default_field_support("unknown"),
    }

    # Scan for a KBP keyboard by service UUID.
    print(
        f"scanning for KBP keyboards (service={SERVICE_UUID}, timeout={args.timeout}s) ...",
        file=sys.stderr,
    )
    try:
        devices = await BleakScanner.discover(
            timeout=args.timeout, service_uuids=[SERVICE_UUID]
        )
    except BleakError as exc:
        _env_error(f"bleak scan failed: {exc}")
        return extras
    except OSError as exc:
        # Linux (BlueZ): "No powered Bluetooth adapter"; Windows: BLE radio off.
        _env_error(f"Bluetooth adapter error: {exc}")
        return extras

    candidate = _choose_candidate(devices, args.device_filter)
    if candidate is None:
        _env_error(
            "no KBP keyboard found by active scan. "
            "Note: a connected BLE HID keyboard stops advertising, so you may need "
            "to disconnect+reconnect it, or run conformance_tool_macos.py (macOS only) "
            "which enumerates connected peripherals."
        )
        return extras

    extras["keyboard"] = {
        "name": candidate.name,
        "address": candidate.address,
    }
    print(f'found: "{candidate.name}" ({candidate.address})', file=sys.stderr)

    # Connect + discover characteristics.
    try:
        async with BleakClient(candidate, timeout=args.timeout) as client:
            if not client.is_connected:
                _env_error(f"failed to connect to {candidate.address}")
                return extras
            services = client.services
            await _probe_characteristics(services, extras, report)
            declared_minor = report.determine_declared_minor(
                {k: v.get("present", False) for k, v in extras["characteristics_present"].items()}
            )
            extras["declared_minor"] = declared_minor
            extras["field_support"] = default_field_support(declared_minor)

            # KBP 1.1: READ Connectivity once to populate capability_bits in the
            # JSON output. This is a Foundational-phase enrichment per
            # tasks.md T022; per-field semantic checks (C7-C12) still SKIP
            # until the US-phase tasks implement them.
            if declared_minor == "1.1":
                await _populate_capability_bits(client, extras)

            # Foundational-phase: C1-C6 and C7-C12 are left as SKIP with a note
            # pointing at the US-phase tasks that will fill them in. The
            # scaffolding itself (discovery + connect + GATT walk) is validated
            # by the fact that we got this far without an environment error.
            _mark_skip_with_us_phase_notes(report)

            # Observe briefly to make the human-readable output feel complete.
            await asyncio.sleep(min(args.observe, 2.0))
    except BleakError as exc:
        _env_error(f"BLE connection error: {exc}")
    except asyncio.TimeoutError:
        _env_error(f"connect/discover timed out after {args.timeout}s")

    return extras


async def _populate_capability_bits(client, extras: dict[str, Any]) -> None:
    """READ the Connectivity characteristic once and record `capability_bits`
    in `extras` so the JSON output's §4.1 schema is complete.

    Does not mark C7-C12 — those are US-phase deliverables. Errors here are
    swallowed into a diagnostic field in `extras`, not an environment error.
    """
    try:
        raw = await client.read_gatt_char(CHAR_CONNECTIVITY_UUID)
    except Exception as exc:  # noqa: BLE001 — any BLE failure here is non-fatal
        extras["capability_bits_read_error"] = str(exc)
        return
    parsed = parse_connectivity(bytes(raw))
    if parsed is None:
        extras["capability_bits_read_error"] = (
            f"Connectivity payload shorter than 7 bytes ({len(raw)} bytes)"
        )
        return
    bits = parsed["capability_bits"]
    extras["capability_bits"] = {
        "raw": f"0x{bits['raw']:02X}",
        "is_split": bits["is_split"],
        "has_host_connection": bits["has_host_connection"],
        "has_profile": bits["has_profile"],
        "has_split_link": bits["has_split_link"],
        "has_output_endpoint": bits["has_output_endpoint"],
        "has_left_charging": bits["has_left_charging"],
        "has_right_charging": bits["has_right_charging"],
    }


def _choose_candidate(devices: list, device_filter: str | None):
    if not devices:
        return None
    if not device_filter:
        return devices[0]
    needle = device_filter.lower()
    for dev in devices:
        if dev.name and needle in dev.name.lower():
            return dev
    return devices[0]


async def _probe_characteristics(services, extras: dict[str, Any], report: Report) -> None:
    """Walk GATT services, record characteristic presence + properties + CCC."""
    present = {
        "AA440AA1": {"present": False, "properties": [], "ccc": False},
        "AA440AA2": {"present": False, "properties": [], "ccc": False},
        "AA440AA3": {"present": False, "properties": [], "ccc": False},
    }
    for service in services:
        if service.uuid.lower() != SERVICE_UUID:
            continue
        for char in service.characteristics:
            uuid_lower = char.uuid.lower()
            short_key = None
            if uuid_lower == CHAR_STATUS_UUID:
                short_key = "AA440AA1"
            elif uuid_lower == CHAR_CONNECTIVITY_UUID:
                short_key = "AA440AA2"
            elif uuid_lower == CHAR_BATTERY_UUID:
                short_key = "AA440AA3"
            if short_key is None:
                continue
            props = sorted(set(p.upper() for p in char.properties))
            has_ccc = any(
                d.uuid.lower() == CCC_DESCRIPTOR_UUID for d in char.descriptors
            )
            present[short_key] = {
                "present": True,
                "properties": props,
                "ccc": has_ccc,
            }
    extras["characteristics_present"] = present


def _mark_skip_with_us_phase_notes(report: Report) -> None:
    """Phase 2 (Foundational) does not implement per-field checks. Each item is
    left as SKIP with a pointer to the US-phase task that will implement it.

    This matches tasks.md T009's scope: "此 task **不**实现 C7–C12 字段级
    检查,只搭骨架 + 跳过".
    """
    us_notes = {
        "C1": ("SKIP", "implemented in user story 1 (T025 host/profile field checks)"),
        "C2": ("SKIP", "implemented in user story 1 (T025 payload length + UTF-8)"),
        "C3": ("SKIP", "implemented in user story 1 (T025 NOTIFY observation)"),
        "C4": ("SKIP", "implemented in user story 1 (T025 connected-peripheral enum)"),
        "C5": ("SKIP", "implemented in user story 1 (T025 GAP name observation)"),
        "C6": ("MANUAL", "verify in firmware build config: service only in central image"),
        "C7": ("SKIP", "implemented in user story phases (T025/T031/T035/T039)"),
        "C8": ("SKIP", "implemented in user story phases (T025/T031/T035/T039)"),
        "C9": ("SKIP", "implemented in user story 2 (T031 Battery characteristic checks)"),
        "C10": ("SKIP", "implemented in user story phases (T025 NOTIFY on state change)"),
        "C11": ("SKIP", "implemented in user story 2 (T031 Battery NOTIFY throttling)"),
        "C12": ("MANUAL", "verify in firmware: 1.1 characteristics only in central image"),
    }
    for item_id, (status, note) in us_notes.items():
        report.set(item_id, status, note)


# -----------------------------------------------------------------------------
# Environment error handling (exit 2)
# -----------------------------------------------------------------------------


_env_error_raised = False


def _env_error(msg: str) -> None:
    """Signal an environment error. Printed to stderr; caller returns exit 2."""
    global _env_error_raised
    _env_error_raised = True
    print(f"environment error: {msg}", file=sys.stderr)


# -----------------------------------------------------------------------------
# Main entry
# -----------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description=(
            "KBP 1.0 + 1.1 conformance self-test (cross-platform via bleak). "
            "See contracts/conformance-cli.md for the normative contract."
        ),
    )
    ap.add_argument(
        "--timeout",
        type=float,
        default=15.0,
        help="BLE discovery / connect timeout in seconds (default: 15)",
    )
    ap.add_argument(
        "--observe",
        type=float,
        default=10.0,
        help="Post-connect observation window to validate NOTIFY behavior (default: 10)",
    )
    ap.add_argument(
        "--json",
        action="store_true",
        help="Emit the support-matrix as JSON on stdout; suppress human-readable output",
    )
    ap.add_argument(
        "--device-filter",
        type=str,
        default=None,
        metavar="NAME",
        help="Partial GAP-name match to pick a specific keyboard when multiple are present",
    )
    ap.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI color in human-readable output",
    )
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    report = Report(use_color=not args.no_color)

    # Run the async discovery + check pipeline.
    try:
        extras = asyncio.run(discover_and_check(args, report))
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        return EXIT_ENV

    if _env_error_raised:
        if args.json:
            # Even on env error, emit a well-formed JSON object with exit_code=2.
            extras.setdefault("declared_minor", "unknown")
            json_out = report.to_json(extras)
            json_out["exit_code"] = EXIT_ENV
            json_out["verdict"] = "environment_error"
            print(json.dumps(json_out, ensure_ascii=False, indent=2))
        return EXIT_ENV

    exit_code = report.determine_exit_code()
    if args.json:
        print(json.dumps(report.to_json(extras), ensure_ascii=False, indent=2))
    else:
        report.render_human(extras)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
