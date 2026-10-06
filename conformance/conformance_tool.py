#!/usr/bin/env python3
# Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# KeyBeacon Protocol (KBP) conformance self-test.
#
# Evolves the developer probe into a checklist runner: it discovers a candidate
# keyboard **by the KBP service UUID alone** (never by name/make/model), confirms
# the service over GATT, then runs the KBP §10 checklist and prints a per-item
# PASS / FAIL / WARN result naming any specific nonconformance.
#
# Exit codes (contract protocol-standard.md §4):
#   0  all required items pass        (keyboard conforms to KBP 1.x)
#   1  a required conformance item failed
#   2  environment error (Bluetooth off, no keyboard, connect timeout, bad deps)
#
# macOS / CoreBluetooth: a connected BLE HID keyboard stops advertising, so this
# enumerates CONNECTED peripherals (retrieveConnectedPeripheralsWithServices:)
# and uses active scanning only as a fallback for a not-yet-connected keyboard.
# Discovery by connected-enumeration is itself the evidence for checklist item 4.
#
# Usage (macOS):
#   python3 conformance/conformance_tool.py [--timeout SEC] [--observe SEC]
# Requires PyObjC CoreBluetooth:
#   pip install pyobjc-framework-CoreBluetooth

import argparse
import datetime
import sys

try:
    import objc
    from Foundation import NSObject
    import CoreBluetooth as CB
    from PyObjCTools import AppHelper
except Exception as exc:  # pragma: no cover - environment dependency guard
    sys.stderr.write(
        "environment error: CoreBluetooth (PyObjC) is unavailable: %s\n"
        "install with: pip install pyobjc-framework-CoreBluetooth\n" % exc
    )
    raise SystemExit(2)

SERVICE_UUID = CB.CBUUID.UUIDWithString_("AA440AA0-F5ED-4C48-84A1-8062D20D3D55")
CHAR_UUID = CB.CBUUID.UUIDWithString_("AA440AA1-F5ED-4C48-84A1-8062D20D3D55")
HID_UUID = CB.CBUUID.UUIDWithString_("1812")
CCC_UUID = CB.CBUUID.UUIDWithString_("2902")

POWERED_ON = getattr(CB, "CBManagerStatePoweredOn", 5)
PROP_READ = getattr(CB, "CBCharacteristicPropertyRead", 0x02)
PROP_NOTIFY = getattr(CB, "CBCharacteristicPropertyNotify", 0x10)

EXIT_PASS, EXIT_FAIL, EXIT_ENV = 0, 1, 2

# Required items gate the exit code; RECOMMENDED/MANUAL items only warn.
REQUIRED = {"C1", "C2", "C3", "C4"}


def _ts():
    return datetime.datetime.now().strftime("%H:%M:%S")


def _nsdata_to_bytes(d):
    if d is None:
        return b""
    try:
        return bytes(d)
    except Exception:
        n = int(d.length())
        return bytes(bytearray(d.bytes()[:n]))


def _uuid_eq(a, b):
    return a.UUIDString().lower() == b.UUIDString().lower()


class Report:
    """Collects per-item results and renders the final PASS/FAIL summary."""

    ORDER = ["C1", "C2", "C3", "C4", "C5", "C6"]
    TITLES = {
        "C1": "Service + characteristic (READ|NOTIFY, CCC present)",
        "C2": "READ snapshot >= 2 bytes; layer_name valid UTF-8 or empty",
        "C3": "NOTIFY enabled & change-suppressed (no idle traffic)",
        "C4": "Discoverable while connected (connected-peripheral enumeration)",
        "C5": "Non-empty GAP device name (RECOMMENDED)",
        "C6": "Split: feature only on the central (host-link) role (MANUAL)",
    }

    def __init__(self):
        self.results = {}

    def set(self, item, status, detail=""):
        self.results[item] = (status, detail)

    def render_and_exit(self, gap_name=None):
        print("\n==== KBP 1.x conformance ====")
        if gap_name is not None:
            print('discovered GAP name: "%s"  (confirm this is your keyboard)' % gap_name)
        print("")
        failed = False
        for item in self.ORDER:
            status, detail = self.results.get(item, ("SKIP", "not evaluated"))
            mark = {
                "PASS": "PASS", "FAIL": "FAIL", "WARN": "WARN",
                "MANUAL": "MANUAL", "SKIP": "SKIP",
            }.get(status, status)
            line = "  [%-6s] %s: %s" % (mark, item, self.TITLES[item])
            if detail:
                line += "\n            -> %s" % detail
            print(line)
            if status == "FAIL" and item in REQUIRED:
                failed = True
        print("")
        if failed:
            print("RESULT: FAIL — one or more required KBP items did not conform.")
            _exit(EXIT_FAIL)
        print("RESULT: PASS — keyboard conforms to KBP 1.x (see WARN/MANUAL notes).")
        _exit(EXIT_PASS)


def _exit(code):
    try:
        AppHelper.stopEventLoop()
    except Exception:
        pass
    sys.exit(code)


def _env_error(msg):
    sys.stderr.write("environment error: %s\n" % msg)
    _exit(EXIT_ENV)


class Conformance(NSObject):
    def initWithArgs_(self, args):
        self = objc.super(Conformance, self).init()
        if self is None:
            return None
        self.timeout = args.timeout
        self.observe = args.observe
        self.manager = None
        self.peripheral = None
        self.characteristic = None
        self.candidates = []
        self.cand_i = 0
        self.connected = False
        self.scanning = False
        self.found_via = None          # "connected" | "scan"
        self.report = Report()
        self.gap_name = None
        self.initial_read_done = False
        self.idle_updates = 0
        self.subscribed = False
        return self

    # --- central manager delegate ---

    def centralManagerDidUpdateState_(self, central):
        state = central.state()
        if state != POWERED_ON:
            _env_error("Bluetooth is not powered on (state=%s). "
                       "Turn Bluetooth on and retry." % state)
            return
        conn = central.retrieveConnectedPeripheralsWithServices_(
            [HID_UUID, SERVICE_UUID]
        )
        self.candidates = list(conn)
        if self.candidates:
            self.found_via = "connected"
            print("found %d connected candidate(s): %s"
                  % (len(self.candidates),
                     [str(p.name()) for p in self.candidates]))
            self._try_next()
        else:
            print("no connected keyboard found; scanning by service UUID "
                  "(connect the keyboard to this Mac for the reliable path) ...")
            self.found_via = "scan"
            self.scanning = True
            central.scanForPeripheralsWithServices_options_([SERVICE_UUID], None)
            AppHelper.callLater(self.timeout, self._scan_timeout)

    def _try_next(self):
        if self.cand_i >= len(self.candidates):
            _env_error("no KeyBeacon keyboard found (no connected candidate "
                       "exposes service AA440AA0-…). Connect a KBP keyboard "
                       "and retry.")
            return
        p = self.candidates[self.cand_i]
        self.cand_i += 1
        self.peripheral = p
        p.setDelegate_(self)
        print("connecting to %s ..." % (p.name() or p.identifier().UUIDString()))
        self.manager.connectPeripheral_options_(p, None)
        AppHelper.callLater(self.timeout, self._connect_timeout_for_, p)

    def _connect_timeout_for_(self, p):
        if not self.connected and self.peripheral is p:
            _env_error("connect timed out after %gs. Is the keyboard on and "
                       "in range?" % self.timeout)

    def _scan_timeout(self):
        if not self.connected:
            _env_error("scan found no KeyBeacon keyboard in %gs. Is the "
                       "keyboard on and in range?" % self.timeout)

    def centralManager_didDiscoverPeripheral_advertisementData_RSSI_(
        self, central, peripheral, adv, rssi
    ):
        if self.scanning:
            self.scanning = False
            central.stopScan()
            self.candidates = [peripheral]
            self.cand_i = 0
            self._try_next()

    def centralManager_didConnectPeripheral_(self, central, peripheral):
        self.connected = True
        self.gap_name = peripheral.name()
        print("connected; discovering status service ...")
        peripheral.discoverServices_([SERVICE_UUID])

    def centralManager_didFailToConnectPeripheral_error_(
        self, central, peripheral, error
    ):
        print("failed to connect: %s" % error)
        self.connected = False
        self._try_next()

    # --- peripheral delegate ---

    def peripheral_didDiscoverServices_(self, peripheral, error):
        if error is not None:
            print("service discovery error: %s" % error)
            self._try_next()
            return
        svc = None
        for s in (peripheral.services() or []):
            if _uuid_eq(s.UUID(), SERVICE_UUID):
                svc = s
                break
        if svc is None:
            # This connected device is simply not a KeyBeacon keyboard — keep looking.
            print("  (service not present on this peripheral; trying next)")
            self.connected = False
            self._try_next()
            return
        # Item 4: discovered while connected via connected-peripheral enumeration.
        if self.found_via == "connected":
            self.report.set("C4", "PASS",
                            "found via connected-peripheral enumeration while the "
                            "keyboard was connected (stopped advertising).")
        else:
            self.report.set("C4", "WARN",
                            "found via active scan (keyboard was not connected to "
                            "this Mac); connect it and re-run to verify item 4.")
        peripheral.discoverCharacteristics_forService_([CHAR_UUID], svc)

    def peripheral_didDiscoverCharacteristicsForService_error_(
        self, peripheral, service, error
    ):
        if error is not None:
            print("characteristic discovery error: %s" % error)
            self.report.set("C1", "FAIL", "characteristic discovery failed: %s" % error)
            self.report.render_and_exit(self.gap_name)
            return
        ch = None
        for c in (service.characteristics() or []):
            if _uuid_eq(c.UUID(), CHAR_UUID):
                ch = c
                break
        if ch is None:
            self.report.set("C1", "FAIL",
                            "status characteristic AA440AA1-… not found on the service.")
            self.report.render_and_exit(self.gap_name)
            return
        self.characteristic = ch
        props = int(ch.properties())
        missing = []
        if not (props & PROP_READ):
            missing.append("READ")
        if not (props & PROP_NOTIFY):
            missing.append("NOTIFY")
        if missing:
            self.report.set("C1", "FAIL",
                            "characteristic is missing required propert%s: %s"
                            % ("y" if len(missing) == 1 else "ies", ", ".join(missing)))
            self.report.render_and_exit(self.gap_name)
            return
        # Need the CCC descriptor to complete item 1.
        peripheral.discoverDescriptorsForCharacteristic_(ch)

    def peripheral_didDiscoverDescriptorsForCharacteristic_error_(
        self, peripheral, characteristic, error
    ):
        has_ccc = False
        for d in (characteristic.descriptors() or []):
            if _uuid_eq(d.UUID(), CCC_UUID):
                has_ccc = True
                break
        if not has_ccc:
            self.report.set("C1", "FAIL",
                            "no Client Characteristic Configuration (CCC/0x2902) "
                            "descriptor — NOTIFY cannot be subscribed per spec.")
            self.report.render_and_exit(self.gap_name)
            return
        self.report.set("C1", "PASS",
                        "service + characteristic present with READ|NOTIFY and CCC.")
        print("reading initial snapshot + subscribing ...")
        peripheral.readValueForCharacteristic_(characteristic)
        peripheral.setNotifyValue_forCharacteristic_(True, characteristic)

    def peripheral_didUpdateNotificationStateForCharacteristic_error_(
        self, peripheral, characteristic, error
    ):
        if error is not None:
            self.report.set("C3", "FAIL", "failed to enable NOTIFY: %s" % error)
            self.report.render_and_exit(self.gap_name)
            return
        self.subscribed = True

    def peripheral_didUpdateValueForCharacteristic_error_(
        self, peripheral, characteristic, error
    ):
        if error is not None:
            if not self.initial_read_done:
                self.report.set("C2", "FAIL", "READ failed: %s" % error)
                self.report.render_and_exit(self.gap_name)
            return
        data = _nsdata_to_bytes(characteristic.value())
        if not self.initial_read_done:
            self.initial_read_done = True
            self._check_payload(data)
            # Observe an idle window to confirm change-suppression (no idle spam).
            print("observing %gs for idle traffic (do not touch the keyboard) ..."
                  % self.observe)
            AppHelper.callLater(self.observe, self._finalize)
        else:
            # Any value arriving after the initial READ, while idle, is a notify.
            self.idle_updates += 1
            print("  [%s] idle update: %s" % (_ts(), self._fmt(data)))

    # --- checks ---

    def _fmt(self, data):
        if len(data) < 2:
            return "<short packet, %d bytes>" % len(data)
        name = data[2:].decode("utf-8", errors="replace")
        return "layer_index=%d mods=0x%02x name=%r" % (data[0], data[1], name)

    def _check_payload(self, data):
        print("  initial READ: %s" % self._fmt(data))
        if len(data) < 2:
            self.report.set("C2", "FAIL",
                            "snapshot is %d byte(s); KBP requires >= 2." % len(data))
            return
        try:
            data[2:].decode("utf-8")
            self.report.set("C2", "PASS",
                            "%d-byte snapshot; layer_name is valid UTF-8%s."
                            % (len(data), " (empty)" if len(data) == 2 else ""))
        except UnicodeDecodeError:
            self.report.set("C2", "FAIL",
                            "layer_name bytes are not valid UTF-8.")

    def _finalize(self):
        if not self.subscribed:
            self.report.set("C3", "FAIL",
                            "NOTIFY subscription was not confirmed.")
        elif self.idle_updates == 0:
            self.report.set("C3", "PASS",
                            "subscribed; no notifications while idle (change-"
                            "suppression consistent). Switch layers to see live updates.")
        else:
            self.report.set("C3", "FAIL",
                            "%d notification(s) arrived while idle — change "
                            "suppression (spec §5) appears broken." % self.idle_updates)
        # Item 5 (RECOMMENDED): GAP name.
        if self.gap_name and str(self.gap_name).strip():
            self.report.set("C5", "PASS", 'GAP name = "%s".' % self.gap_name)
        else:
            self.report.set("C5", "WARN",
                            "no GAP device name; host will use a generic fallback "
                            "(RECOMMENDED, not required).")
        # Item 6: not host-observable.
        self.report.set("C6", "MANUAL",
                        "verify in firmware config that the service is built only "
                        "into the central (host-link) image, not peripheral/reset.")
        self.report.render_and_exit(self.gap_name)


def main():
    ap = argparse.ArgumentParser(description="KBP 1.x conformance self-test")
    ap.add_argument("--timeout", type=float, default=15.0,
                    help="seconds to wait for discovery/connect (default 15)")
    ap.add_argument("--observe", type=float, default=4.0,
                    help="idle-observation window for change-suppression (default 4)")
    args = ap.parse_args()

    runner = Conformance.alloc().initWithArgs_(args)
    runner.manager = CB.CBCentralManager.alloc().initWithDelegate_queue_(runner, None)
    print("starting KBP conformance self-test (CoreBluetooth) ...")
    try:
        AppHelper.runConsoleEventLoop(installInterrupt=True)
    except KeyboardInterrupt:
        sys.stderr.write("\ninterrupted\n")
        return EXIT_ENV
    return EXIT_PASS


if __name__ == "__main__":
    sys.exit(main())
