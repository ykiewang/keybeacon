// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import Foundation
import CoreBluetooth

public final class KeymapDataFetcher {
    public static let keymapMetaUUID = CBUUID(string: "AA440AA5-F5ED-4C48-84A1-8062D20D3D55")
    public static let keymapDataUUID = CBUUID(string: "AA440AA6-F5ED-4C48-84A1-8062D20D3D55")

    public typealias Completion = (Result<KeymapSnapshot, Error>) -> Void

    public enum FetchError: Error {
        case noPeripheral
        case noCharacteristic
        case readFailed(Error)
        case parseFailed
    }

    private weak var peripheral: CBPeripheral?
    private var metaCharacteristic: CBCharacteristic?
    private var dataCharacteristic: CBCharacteristic?

    private var metaCompletion: ((Result<Data, Error>) -> Void)?
    private var dataCompletion: ((Result<Data, Error>) -> Void)?
    private var accumulatedData = Data()
    private var expectedLength: Int?
    private var activeHandler: ReadBlobHandler?

    public init(peripheral: CBPeripheral?,
                metaCharacteristic: CBCharacteristic?,
                dataCharacteristic: CBCharacteristic?) {
        self.peripheral = peripheral
        self.metaCharacteristic = metaCharacteristic
        self.dataCharacteristic = dataCharacteristic
    }

    public func fetch(ignoreCache: Bool = false,
                      keyboardID: UUID,
                      settings: AppSettings,
                      completion: @escaping Completion) {
        guard let peripheral else {
            completion(.failure(FetchError.noPeripheral))
            return
        }
        guard let metaChar = metaCharacteristic else {
            completion(.failure(FetchError.noCharacteristic))
            return
        }

        readFull(peripheral: peripheral, characteristic: metaChar) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                completion(.failure(FetchError.readFailed(err)))
            case .success(let metaData):
                guard let meta = KeymapMeta.parse(metaData) else {
                    completion(.failure(FetchError.parseFailed))
                    return
                }
                if !ignoreCache,
                   let cached = settings.keymapSnapshot(for: keyboardID, crc32: meta.crc32) {
                    completion(.success(cached))
                    return
                }
                guard let dataChar = self.dataCharacteristic else {
                    completion(.failure(FetchError.noCharacteristic))
                    return
                }
                self.readFull(peripheral: peripheral, characteristic: dataChar) { dataResult in
                    switch dataResult {
                    case .failure(let err):
                        completion(.failure(FetchError.readFailed(err)))
                    case .success(let rawData):
                        guard let snapshot = KeymapSnapshot.parse(meta: meta, data: rawData) else {
                            completion(.failure(FetchError.parseFailed))
                            return
                        }
                        settings.setKeymapSnapshot(snapshot, for: keyboardID, crc32: meta.crc32)
                        completion(.success(snapshot))
                    }
                }
            }
        }
    }

    private func readFull(peripheral: CBPeripheral,
                          characteristic: CBCharacteristic,
                          completion: @escaping (Result<Data, Error>) -> Void) {
        accumulatedData = Data()
        expectedLength = nil
        let handler = ReadBlobHandler(peripheral: peripheral,
                                      characteristic: characteristic,
                                      completion: { [weak self] result in
            self?.activeHandler = nil
            completion(result)
        })
        activeHandler = handler
        handler.start()
    }
}

final class ReadBlobHandler: NSObject, CBPeripheralDelegate {
    private let peripheral: CBPeripheral
    private let characteristic: CBCharacteristic
    private let completion: (Result<Data, Error>) -> Void
    private var accumulated = Data()
    private var previousDelegate: CBPeripheralDelegate?

    init(peripheral: CBPeripheral,
         characteristic: CBCharacteristic,
         completion: @escaping (Result<Data, Error>) -> Void) {
        self.peripheral = peripheral
        self.characteristic = characteristic
        self.completion = completion
    }

    func start() {
        previousDelegate = peripheral.delegate
        peripheral.delegate = self
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == self.characteristic.uuid else { return }
        if let error {
            peripheral.delegate = previousDelegate
            completion(.failure(error))
            return
        }
        guard let chunk = characteristic.value else {
            peripheral.delegate = previousDelegate
            completion(.success(accumulated))
            return
        }
        accumulated.append(chunk)
        if chunk.count < 512 {
            peripheral.delegate = previousDelegate
            completion(.success(accumulated))
        } else {
            peripheral.readValue(for: characteristic)
        }
    }
}
