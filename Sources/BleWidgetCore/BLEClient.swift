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
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var knownIdentifier: UUID?
    private var activeKeyboard: CompatibleKeyboard?
    private var candidatePeripherals: [CBPeripheral] = []
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
        knownIdentifier = identifier
        if let current = peripheral, current.identifier != identifier {
            central.cancelPeripheralConnection(current)
            peripheral = nil
            characteristic = nil
            activeKeyboard = nil
        }
        if let p = candidatePeripherals.first(where: { $0.identifier == identifier })
            ?? central.retrievePeripherals(withIdentifiers: [identifier]).first {
            connect(p)
        } else {
            scheduleReconnect()
        }
    }

    private func attemptConnect() {
        guard central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(
            withServices: [Self.hidServiceUUID, Self.serviceUUID]
        )
        candidatePeripherals = connected
        publishCandidates()

        if peripheral != nil { return }

        let ids = connected.map { $0.identifier }
        if let chosen = CompatibleKeyboard.resolveSelection(
               candidates: ids, remembered: settings.selectedKeyboardIdentifier
           ),
           let p = connected.first(where: { $0.identifier == chosen }) {
            settings.selectedKeyboardIdentifier = chosen
            knownIdentifier = chosen
            connect(p)
        } else {
            scheduleReconnect()
        }
    }

    private func publishCandidates() {
        let active = activeKeyboard?.identifier
        let list = candidatePeripherals.map { p in
            CompatibleKeyboard(
                identifier: p.identifier,
                name: p.name,
                state: p.identifier == active ? .connected : .notConnected,
                isCompatible: true
            )
        }
        delegate?.bleClient(self, didUpdateCandidates: list)
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
        delegate?.bleClient(self, didChangeState: .connecting)
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(
            withTimeInterval: reconnectInterval, repeats: false
        ) { [weak self] _ in
            self?.attemptConnect()
        }
    }

    private func tearDown() {
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
        knownIdentifier = peripheral.identifier
        peripheral.discoverServices([Self.serviceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        self.characteristic = nil
        activeKeyboard = nil
        delegate?.bleClient(self, didChangeState: .notConnected)
        delegate?.bleClient(self, didChangeActiveKeyboard: nil)
        publishCandidates()
        scheduleReconnect()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        activeKeyboard = nil
        delegate?.bleClient(self, didChangeState: .notConnected)
        delegate?.bleClient(self, didChangeActiveKeyboard: nil)
        publishCandidates()
        scheduleReconnect()
    }
}

extension BLEClient: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        let discovered = (peripheral.services ?? []).map { $0.uuid }
        guard CompatibleKeyboard.isCompatible(discoveredServiceUUIDs: discovered),
              let service = peripheral.services?.first(
                  where: { $0.uuid == Self.serviceUUID }
              )
        else {
            central.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
            scheduleReconnect(); return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let ch = service.characteristics?.first(
            where: { $0.uuid == Self.characteristicUUID }
        ) else { return }
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
