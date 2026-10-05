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

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var knownIdentifier: UUID?
    private var reconnectTimer: Timer?
    private let reconnectInterval: TimeInterval = 3

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func start() {
        attemptConnect()
    }

    private func attemptConnect() {
        guard central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(
            withServices: [Self.hidServiceUUID, Self.serviceUUID]
        )
        let candidate = connected.first {
            $0.name?.localizedCaseInsensitiveContains("TOTEM") == true ||
            ($0.identifier == knownIdentifier)
        }
        if let p = candidate {
            connect(p)
        } else {
            scheduleReconnect()
        }
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
        delegate?.bleClient(self, didChangeState: .notConnected)
        scheduleReconnect()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        delegate?.bleClient(self, didChangeState: .notConnected)
        scheduleReconnect()
    }
}

extension BLEClient: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard let service = peripheral.services?.first(
            where: { $0.uuid == Self.serviceUUID }
        ) else {
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
        delegate?.bleClient(self, didChangeState: .connected)
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
