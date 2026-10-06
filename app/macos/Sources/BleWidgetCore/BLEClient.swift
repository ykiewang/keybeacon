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
}

public extension BLEClientDelegate {
    func bleClient(_ client: BLEClient, didChangeActiveKeyboard keyboard: CompatibleKeyboard?) {}
    func bleClient(_ client: BLEClient, didUpdateCandidates keyboards: [CompatibleKeyboard]) {}
}

public final class BLEClient: NSObject {
    private static let serviceUUID = CBUUID(
        string: "AA440AA0-F5ED-4C48-84A1-8062D20D3D55"
    )
    private static let characteristicUUID = CBUUID(
        string: "AA440AA1-F5ED-4C48-84A1-8062D20D3D55"
    )
    private static let hidServiceUUID = CBUUID(string: "1812")

    public weak var delegate: BLEClientDelegate?

    private let settings = AppSettings()
    private var central: CBCentralManager!

    // Committed (active) connection.
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var activeKeyboard: CompatibleKeyboard?

    // Discovery scan: connect each potential, confirm the custom service via
    // GATT, and keep only genuinely compatible keyboards (identity by service,
    // not by name). Compatible peripherals stay connected through the scan so
    // the chosen one is activated in place — no disconnect/reconnect race.
    private var scanQueue: [CBPeripheral] = []
    private var confirmedCompatible: [CBPeripheral] = []
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
            releaseConfirmed()
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
            p.discoverCharacteristics([Self.characteristicUUID], for: service)
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
        activeKeyboard = nil
        reconnectTimer?.invalidate()
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
        peripheral.discoverServices([Self.serviceUUID])
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
        let compatible = CompatibleKeyboard.isCompatible(
            discoveredServiceUUIDs: discovered
        )

        if probeTarget === peripheral {
            if compatible {
                confirmedCompatible.append(peripheral)  // keep connected
            } else {
                central.cancelPeripheralConnection(peripheral)
            }
            probeTarget = nil
            probeNext()
            return
        }

        guard self.peripheral === peripheral else { return }
        guard compatible,
              let service = peripheral.services?.first(
                  where: { $0.uuid == Self.serviceUUID }
              )
        else {
            central.cancelPeripheralConnection(peripheral)
            dropActiveConnection()
            scheduleReconnect()
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard self.peripheral === peripheral,
              let ch = service.characteristics?.first(
                  where: { $0.uuid == Self.characteristicUUID }
              )
        else { return }
        characteristic = ch
        peripheral.readValue(for: ch)
        peripheral.setNotifyValue(true, for: ch)
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
        publishCandidates()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        guard let status = KeyboardStatus.parse(data) else { return }
        delegate?.bleClient(self, didUpdate: status)
    }
}
