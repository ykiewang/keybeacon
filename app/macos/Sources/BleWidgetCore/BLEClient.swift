// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import Foundation
import CoreBluetooth

public enum BLEConnectionState {
    case connecting
    case connected
    case notConnected
    case unavailable
}

public protocol BLEClientDelegate: AnyObject {
    func bleClient(_ client: BLEClient, didUpdate status: KeyboardStatus)
    func bleClient(_ client: BLEClient, didChangeState state: BLEConnectionState)
    func bleClient(_ client: BLEClient, didChangeActiveKeyboard keyboard: CompatibleKeyboard?)
    func bleClient(_ client: BLEClient, didUpdateCandidates keyboards: [CompatibleKeyboard])
    /// A KeyBeacon-family keyboard was found whose protocol version this app does
    /// not support (unknown/newer service UUID). It is NOT connected/parsed; the
    /// host surfaces a clear "unsupported protocol version" message (FR-014, SC-007).
    func bleClient(_ client: BLEClient, didDetectUnsupported keyboards: [CompatibleKeyboard])
    /// KBP 1.1 Connectivity characteristic update (optional characteristic;
    /// delegate receives this only when the keyboard exposes `AA440AA2-…`).
    func bleClient(_ client: BLEClient, didUpdateConnectivity status: ConnectivityStatus)
    /// KBP 1.1 Battery characteristic update (optional characteristic;
    /// delegate receives this only when the keyboard exposes `AA440AA3-…`).
    func bleClient(_ client: BLEClient, didUpdateBattery status: BatteryStatus)
    /// `AA440AA2-…` is not present on the connected keyboard — host MUST hide
    /// the entire 1.1 UI card (invariant IV-X1 / U-5). This is a one-shot
    /// callback fired at characteristic-discovery time.
    func bleClient(_ client: BLEClient, didDetermineKBPMinor minor: KBPMinor)
}

public extension BLEClientDelegate {
    func bleClient(_ client: BLEClient, didChangeActiveKeyboard keyboard: CompatibleKeyboard?) {}
    func bleClient(_ client: BLEClient, didUpdateCandidates keyboards: [CompatibleKeyboard]) {}
    func bleClient(_ client: BLEClient, didDetectUnsupported keyboards: [CompatibleKeyboard]) {}
    func bleClient(_ client: BLEClient, didUpdateConnectivity status: ConnectivityStatus) {}
    func bleClient(_ client: BLEClient, didUpdateBattery status: BatteryStatus) {}
    func bleClient(_ client: BLEClient, didDetermineKBPMinor minor: KBPMinor) {}
}

/// Declared MINOR of the currently connected keyboard, derived from GATT
/// characteristic presence (per protocol/README.md §14.5).
public enum KBPMinor: Equatable {
    case onePointZero                      // only AA440AA1-… found
    case onePointOne(hasBattery: Bool)     // AA440AA2-… present; AA440AA3-… optional
    case unknown                           // characteristic discovery incomplete / anomalous
}

public final class BLEClient: NSObject {
    public static let serviceUUID = CBUUID(
        string: "AA440AA0-F5ED-4C48-84A1-8062D20D3D55"
    )
    public static let characteristicUUID = CBUUID(
        string: "AA440AA1-F5ED-4C48-84A1-8062D20D3D55"
    )
    public static let connectivityCharacteristicUUID = CBUUID(
        string: "AA440AA2-F5ED-4C48-84A1-8062D20D3D55"
    )
    public static let batteryCharacteristicUUID = CBUUID(
        string: "AA440AA3-F5ED-4C48-84A1-8062D20D3D55"
    )
    private static let hidServiceUUID = CBUUID(string: "1812")

    public weak var delegate: BLEClientDelegate?

    private let settings = AppSettings()
    private var central: CBCentralManager!

    // Committed (active) connection.
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var connectivityCharacteristic: CBCharacteristic?
    private var batteryCharacteristic: CBCharacteristic?
    private var activeKeyboard: CompatibleKeyboard?

    // Cache of the current CapabilityMatrix for the active keyboard (parsed
    // from the first Connectivity payload). Needed to decide Battery payload
    // length (invariants C-B1 / C-B2).
    private var cachedCapability: CapabilityMatrix?

    // Discovery scan: connect each potential, confirm the custom service via
    // GATT, and keep only genuinely compatible keyboards (identity by service,
    // not by name). Compatible peripherals stay connected through the scan so
    // the chosen one is activated in place — no disconnect/reconnect race.
    private var scanQueue: [CBPeripheral] = []
    private var confirmedCompatible: [CBPeripheral] = []
    private var detectedUnsupported: [CBPeripheral] = []
    private var probeTarget: CBPeripheral?

    private var reconnectTimer: Timer?
    private let reconnectInterval: TimeInterval = 3

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func start() {
        attemptConnect()
    }

    /// Explicit user selection from the menu-bar chooser (FR-014/FR-015/FR-016):
    /// persist the choice and switch the single active connection to it.
    public func select(_ identifier: UUID) {
        settings.selectedKeyboardIdentifier = identifier
        if let current = peripheral, current.identifier != identifier {
            central.cancelPeripheralConnection(current)
            peripheral = nil
            characteristic = nil
            connectivityCharacteristic = nil
            batteryCharacteristic = nil
            cachedCapability = nil
            activeKeyboard = nil
        }
        cancelScan()
        attemptConnect()
    }

    private func attemptConnect() {
        guard central.state == .poweredOn else { return }
        guard peripheral == nil, probeTarget == nil else { return }

        let potentials = central.retrieveConnectedPeripherals(
            withServices: [Self.hidServiceUUID, Self.serviceUUID]
        )
        releaseConfirmed()
        detectedUnsupported = []
        guard !potentials.isEmpty else {
            publishCandidates()
            delegate?.bleClient(self, didChangeState: .notConnected)
            scheduleReconnect()
            return
        }
        scanQueue = potentials
        delegate?.bleClient(self, didChangeState: .connecting)
        probeNext()
    }

    private func probeNext() {
        guard peripheral == nil, probeTarget == nil else { return }
        guard !scanQueue.isEmpty else { finishScan(); return }
        let p = scanQueue.removeFirst()
        probeTarget = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    private func finishScan() {
        publishCandidates()
        let ids = confirmedCompatible.map { $0.identifier }
        guard let chosen = CompatibleKeyboard.resolveSelection(
                  candidates: ids, remembered: settings.selectedKeyboardIdentifier
              ),
              let target = confirmedCompatible.first(where: { $0.identifier == chosen })
        else {
            // Zero compatible → keep retrying; ≥2 compatible and none remembered
            // → await an explicit choice. Release the held probe connections.
            let onlyUnsupported = confirmedCompatible.isEmpty && !detectedUnsupported.isEmpty
            releaseConfirmed()
            if onlyUnsupported {
                let list = detectedUnsupported.map { p in
                    CompatibleKeyboard(
                        identifier: p.identifier,
                        name: p.name,
                        state: .notConnected,
                        isCompatible: false
                    )
                }
                delegate?.bleClient(self, didDetectUnsupported: list)
            }
            delegate?.bleClient(self, didChangeState: .notConnected)
            scheduleReconnect()
            return
        }

        settings.selectedKeyboardIdentifier = chosen
        // Drop the other held compatibles; keep the chosen one connected.
        for other in confirmedCompatible where other.identifier != chosen {
            central.cancelPeripheralConnection(other)
        }
        peripheral = target
        activate(target)
    }

    /// Activate a keyboard that is already connected (its custom service was
    /// confirmed during the scan): discover the characteristic in place.
    private func activate(_ p: CBPeripheral) {
        p.delegate = self
        if let service = p.services?.first(where: { $0.uuid == Self.serviceUUID }) {
            // Discover ALL three characteristics; 1.1 ones MAY be absent.
            p.discoverCharacteristics(
                [
                    Self.characteristicUUID,
                    Self.connectivityCharacteristicUUID,
                    Self.batteryCharacteristicUUID,
                ],
                for: service
            )
        } else {
            p.discoverServices([Self.serviceUUID])
        }
    }

    private func publishCandidates() {
        let active = activeKeyboard?.identifier
        let list = confirmedCompatible.map { p in
            CompatibleKeyboard(
                identifier: p.identifier,
                name: p.name,
                state: p.identifier == active ? .connected : .notConnected,
                isCompatible: true
            )
        }
        delegate?.bleClient(self, didUpdateCandidates: list)
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(
            withTimeInterval: reconnectInterval, repeats: false
        ) { [weak self] _ in
            self?.attemptConnect()
        }
    }

    private func cancelScan() {
        if let p = probeTarget {
            central.cancelPeripheralConnection(p)
        }
        probeTarget = nil
        scanQueue = []
        releaseConfirmed()
    }

    private func releaseConfirmed() {
        let active = peripheral?.identifier
        for p in confirmedCompatible where p.identifier != active {
            central.cancelPeripheralConnection(p)
        }
        confirmedCompatible = []
    }

    private func dropActiveConnection() {
        peripheral = nil
        characteristic = nil
        connectivityCharacteristic = nil
        batteryCharacteristic = nil
        cachedCapability = nil
        activeKeyboard = nil
        delegate?.bleClient(self, didChangeState: .notConnected)
        delegate?.bleClient(self, didChangeActiveKeyboard: nil)
        publishCandidates()
    }

    private func tearDown() {
        cancelScan()
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        characteristic = nil
        connectivityCharacteristic = nil
        batteryCharacteristic = nil
        cachedCapability = nil
        activeKeyboard = nil
        reconnectTimer?.invalidate()
    }

    // MARK: - KBP 1.1 handlers

    /// Decode a Connectivity payload (byte-level contract in protocol/README §14.3).
    private func handleConnectivityUpdate(_ data: Data) {
        guard let status = ConnectivityStatus.parse(from: data) else {
            DiagnosticsLogger.connection.connectivityShortPayload(length: data.count)
            return
        }
        // Consumer rules C-C3 / C-C6 / C-C7: enforce invariants, drop bits that
        // violate them, log capability.inconsistent.
        var effective = status.capability
        if !effective.isConsistent {
            let reasons = inconsistencyReasons(for: effective)
            DiagnosticsLogger.capability.inconsistent(
                byte: effective.rawByte,
                reason: reasons.joined(separator: " | ")
            )
            effective = sanitize(effective)
        }

        // Detect hot-reload (capability byte changed between notifies).
        if let previous = cachedCapability, previous.rawByte != effective.rawByte {
            DiagnosticsLogger.capability.mutated(
                fromByte: previous.rawByte, toByte: effective.rawByte
            )
        } else if cachedCapability == nil {
            DiagnosticsLogger.capability.discovered(
                byte: effective.rawByte,
                isSplit: effective.isSplit,
                hasHostConnection: effective.hasHostConnection,
                hasProfile: effective.hasProfile,
                hasSplitLink: effective.hasSplitLink,
                hasOutputEndpoint: effective.hasOutputEndpoint,
                hasLeftCharging: effective.hasLeftCharging,
                hasRightCharging: effective.hasRightCharging
            )
        }
        cachedCapability = effective

        // Log connection state changes (host_state.connected bit flip).
        DiagnosticsLogger.connection.stateChanged(
            connected: status.link.connected,
            reasonRaw: status.link.lastDisconnectReason.rawValue
        )

        // Clamp profile_index > profile_max_slots → diagnostic log; UI is
        // responsible for the clamping of displayed index.
        if effective.hasProfile,
           status.profile.maxSlots > 0,
           status.profile.index > status.profile.maxSlots {
            DiagnosticsLogger.profile.outOfRange(
                rawIndex: status.profile.index,
                maxSlots: status.profile.maxSlots
            )
        }

        delegate?.bleClient(self, didUpdateConnectivity: status)
    }

    /// Decode a Battery payload. Requires that `cachedCapability.isSplit` is
    /// known (set by `handleConnectivityUpdate`); otherwise defers to the
    /// payload length as a weak heuristic.
    private func handleBatteryUpdate(_ data: Data) {
        let isSplit = cachedCapability?.isSplit ?? (data.count == 2)
        guard let status = BatteryStatus.parse(from: data, isSplit: isSplit) else {
            DiagnosticsLogger.battery.lengthMismatch(
                expected: isSplit ? 2 : 1,
                got: data.count,
                isSplit: isSplit
            )
            return
        }
        // Log out-of-range raw bytes per C-B3.
        switch status.kind {
        case .overall(let reading):
            logBatteryOutOfRange(reading, side: "overall")
        case .split(let left, let right):
            logBatteryOutOfRange(left, side: "left")
            logBatteryOutOfRange(right, side: "right")
        }
        delegate?.bleClient(self, didUpdateBattery: status)
    }

    private func logBatteryOutOfRange(_ reading: BatteryStatus.BatteryReading, side: String) {
        if case .unavailable(let raw, let outOfRange) = reading, outOfRange {
            DiagnosticsLogger.battery.outOfRange(rawByte: raw, side: side)
        }
    }

    private func inconsistencyReasons(for m: CapabilityMatrix) -> [String] {
        var reasons: [String] = []
        if m.hasSplitLink && !m.isSplit {
            reasons.append("IV-C1 has_split_link without is_split")
        }
        if m.hasRightCharging && !m.isSplit {
            reasons.append("IV-C3 has_right_charging without is_split")
        }
        if m.hasRightCharging && !m.hasLeftCharging {
            reasons.append("IV-C3 has_right_charging without has_left_charging")
        }
        return reasons
    }

    private func sanitize(_ m: CapabilityMatrix) -> CapabilityMatrix {
        CapabilityMatrix(
            isSplit: m.isSplit,
            hasHostConnection: m.hasHostConnection,
            hasProfile: m.hasProfile,
            hasSplitLink: m.hasSplitLink && m.isSplit,
            hasOutputEndpoint: m.hasOutputEndpoint,
            hasLeftCharging: m.hasLeftCharging,
            hasRightCharging: m.hasRightCharging && m.isSplit && m.hasLeftCharging,
            reserved7: m.reserved7
        )
    }
}

extension BLEClient: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            attemptConnect()
        case .poweredOff, .unauthorized, .unsupported, .resetting:
            tearDown()
            delegate?.bleClient(self, didChangeState: .unavailable)
        default:
            break
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        // Discover ALL services so an unknown KeyBeacon-family service (an
        // unsupported MAJOR) is visible for classification, not just our own.
        peripheral.discoverServices(nil)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        dropActiveConnection()
        scheduleReconnect()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        if probeTarget === peripheral {
            probeTarget = nil
            probeNext()
            return
        }
        guard self.peripheral === peripheral else { return }
        dropActiveConnection()
        scheduleReconnect()
    }
}

extension BLEClient: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        let discovered = (peripheral.services ?? []).map { $0.uuid }
        let classification = KBPCompatibility.classify(discoveredServices: discovered)

        if probeTarget === peripheral {
            switch classification {
            case .supported:
                confirmedCompatible.append(peripheral)  // keep connected
            case .unsupportedVersion:
                // KeyBeacon-family but a MAJOR we don't support: remember it so the
                // host can report "unsupported protocol version"; never parse it.
                if !detectedUnsupported.contains(where: { $0.identifier == peripheral.identifier }) {
                    detectedUnsupported.append(peripheral)
                }
                central.cancelPeripheralConnection(peripheral)
            case .notAKeyboard:
                central.cancelPeripheralConnection(peripheral)
            }
            probeTarget = nil
            probeNext()
            return
        }

        guard self.peripheral === peripheral else { return }
        guard classification == .supported,
              let service = peripheral.services?.first(
                  where: { $0.uuid == Self.serviceUUID }
              )
        else {
            central.cancelPeripheralConnection(peripheral)
            dropActiveConnection()
            scheduleReconnect()
            return
        }
        peripheral.discoverCharacteristics(
            [
                Self.characteristicUUID,
                Self.connectivityCharacteristicUUID,
                Self.batteryCharacteristicUUID,
            ],
            for: service
        )
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard self.peripheral === peripheral else { return }
        let chars = service.characteristics ?? []
        let statusChar = chars.first { $0.uuid == Self.characteristicUUID }
        let connChar = chars.first { $0.uuid == Self.connectivityCharacteristicUUID }
        let battChar = chars.first { $0.uuid == Self.batteryCharacteristicUUID }

        // The 1.0 characteristic is REQUIRED; without it this is not a
        // conformant keyboard.
        guard let statusChar = statusChar else {
            // Discovery anomaly: service present but AA1 missing.
            if connChar != nil {
                DiagnosticsLogger.connection.discoveryAnomaly(
                    reason: "AA440AA2-… present but AA440AA1-… missing"
                )
            }
            return
        }
        characteristic = statusChar
        peripheral.readValue(for: statusChar)
        peripheral.setNotifyValue(true, for: statusChar)

        // 1.1 characteristics are OPTIONAL. Subscribe only if present.
        connectivityCharacteristic = connChar
        if let connChar = connChar {
            peripheral.readValue(for: connChar)
            peripheral.setNotifyValue(true, for: connChar)
        }
        batteryCharacteristic = battChar
        if let battChar = battChar {
            peripheral.readValue(for: battChar)
            peripheral.setNotifyValue(true, for: battChar)
        }

        let keyboard = CompatibleKeyboard(
            identifier: peripheral.identifier,
            name: peripheral.name,
            state: .connected,
            isCompatible: true
        )
        activeKeyboard = keyboard
        if !confirmedCompatible.contains(where: { $0.identifier == peripheral.identifier }) {
            confirmedCompatible.append(peripheral)
        }
        delegate?.bleClient(self, didChangeState: .connected)
        delegate?.bleClient(self, didChangeActiveKeyboard: keyboard)

        // Signal the declared KBP MINOR to the UI (card visibility, IV-X1 / U-5).
        let minor: KBPMinor
        if connChar != nil {
            minor = .onePointOne(hasBattery: battChar != nil)
        } else {
            minor = .onePointZero
        }
        delegate?.bleClient(self, didDetermineKBPMinor: minor)

        publishCandidates()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case Self.characteristicUUID:
            guard let status = KeyboardStatus.parse(data) else { return }
            delegate?.bleClient(self, didUpdate: status)
        case Self.connectivityCharacteristicUUID:
            handleConnectivityUpdate(data)
        case Self.batteryCharacteristicUUID:
            handleBatteryUpdate(data)
        default:
            break
        }
    }
}
