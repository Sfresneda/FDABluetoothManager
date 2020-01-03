//
//  FDABluetoothManager.swift
//
//  Created by Sergio Fresneda on 12/28/19.
//  Copyright © 2019 Sergio Fresneda. All rights reserved.
//

import Foundation
import UIKit
import CoreBluetooth

class FDABluetoothManager: NSObject {
    
    // MARK: - Variables
    private var spottedDevices: [CBPeripheral]?
    private weak var appDelegate: AppDelegate?
    private var pendingCompletions: [BTMCompletionModel] = []

    weak var delegate: FDABluetoothManagerDelegate?
    
    /// Operated variable allow get/set spottedDevices without handle optionals
    var deviceManager: [CBPeripheral] {
        get {
            guard let wrappedDevices = self.spottedDevices else { return [] }
            return wrappedDevices
        }
        set {
            if self.spottedDevices == nil || newValue.isEmpty { self.spottedDevices = [] }
            
            /// Avoid duplicated peripherals
            newValue.forEach({ newDevice in
                if self.spottedDevices?.filter({
                    $0.identifier.uuidString == newDevice.identifier.uuidString
                }).count ?? 0 < 1 {
                    self.spottedDevices?.append(newDevice)
                }
            })
        }
    }
    
    /// Operated variable for retrieve connected CBPeripherals
    var connectedDevices: [CBPeripheral] {
        return self.centralManager.retrieveConnectedPeripherals(withServices:
            TargetBluetoothDevice.Services.allCases.reduce([], { $0 + [CBUUID.init(string: $1.rawValue)]}))
    }
   
    /// Central Manager shared instance
    var centralManager: CBCentralManager {
        get {
            guard let wrappedAppDelegate = self.appDelegate,
            let wrappedCM = wrappedAppDelegate.centralManager
                else { return CBCentralManager.init() }
            
            return wrappedCM
        }
        set {
            self.appDelegate?.centralManager = newValue
            self.appDelegate?.centralManager.delegate = self
        }
    }
    
    // MARK: - Init
    override init() {
        super.init()
        self.appDelegate = UIApplication.shared.delegate as? AppDelegate
    }
    
    // MARK: - Operation Queue
    
    /// Operation queue for bluetooth actions, only allowed 1 concurrent operation
    private var bluetoothOperationsQueue: OperationQueue = {
        let queueOP = OperationQueue()
        queueOP.maxConcurrentOperationCount = 1
        queueOP.qualityOfService = .background
        queueOP.name = kBTQueueName
        
        return queueOP
    }()
    
    /// Add operation in to Bluetooth operations queue
    ///
    /// - Parameters:
    ///   - operation: operation block
    ///   - priority: priority enumeration
    ///   - caller: only for debug purposes, DONT BIND IT
    func addOperation(operation: BlockOperation,
                      priority: Operation.QueuePriority = .normal,
                      caller: String = #function) {
        operation.queuePriority = priority
        self.bluetoothOperationsQueue.addOperation(operation)
    }
    
    // MARK: - Bluetooth Scan
    
    /// Launch a Bluetooth devices scan
    ///
    /// - Parameters:
    ///   - services: group of services from needed devices
    ///   - success: success completion block
    ///   - failure: failure completion block
    ///   - caller: only for debug purposes, DONT BIND IT
    func scanDevices(_ services: [CBUUID]? = nil,
                     success: @escaping ((BTResponse) -> Void),
                     failure: @escaping ((BTError) -> Void),
                     caller: String = #function) {
        
        /// Check if central manager is ready to user Bluetooth
        guard self.centralManager.state == .poweredOn else {
            self.delegate?.managerInterruption(with: .btNotReady)
            failure(.btNotReady)
            return
        }
        
        /// Stop current scanning task
        if self.centralManager.isScanning {
            self.stopScanDevices()
        }
        
        self.centralManager.scanForPeripherals(withServices: services, options: nil)
        self.delegate?.startScan()
        
        /// Generate a new pending completion with .scan operation
        let completion = self.addPendingCompletion(operation: .scan,
                                  identifiers: [:],
                                  completions: (success, failure))
        
        guard let wrappedCompletion = completion else { return }
        
        /// Add a expiration block with completion model received
        self.addExpirationBlock(self.buildExpirationOperation(type: .scan, model: wrappedCompletion))
    }
    
    /// Stop current scanning task
    ///
    /// - Parameter caller: only for debug purposes, DONT BIND IT
    func stopScanDevices(caller: String = #function) {
        self.centralManager.stopScan()
        
        self.delegate?.stopScan()
        
        /// Stop scan pending operations
        self.cancelOperation(with: scanOperationBlockName)
        self.brutalizePendingCompletion(operations: [.scan,
                                                     .discoverServices,
                                                     .discoverCharacteristics,
                                                     .discoverDescriptors],
                                        identifiers: nil)
    }
    
    /// Launch a connected Bluetooth device services scan
    ///
    /// - Parameters:
    ///   - peripheral: current peripheral to scan services
    ///   - specifiedServices: specified services to check on device
    ///   - caller: only for debug purposes, DONT BIND IT
    ///   - success: success completion block
    ///   - failure: failure completion block
    func scanServices(_ peripheral: CBPeripheral,
                      specifiedServices: [CBUUID]? = nil,
                      caller: String = #function,
                      success: @escaping ((BTResponse) -> Void),
                      failure: @escaping ((BTError) -> Void)) {
        
        peripheral.discoverServices(specifiedServices)
        
        self.delegate?.startServicesScan(peripheral, services: specifiedServices)
        
        /// Generate a new pending completion with .discoverServices operation and discard the result
        _ = self.addPendingCompletion(operation: .discoverServices,
                                  identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                    peripheral.identifier.uuidString],
                                  completions: (success, failure))
    }
    
    /// Launch a connected Bluetooth device characteristics scan
    ///
    /// - Parameters:
    ///   - peripheral: current peripheral to scan characteristics
    ///   - fromSelectesServices: services array fot scan characteristics
    ///   - specifiedCharacteristics: specified characteristics to check on services
    ///   - caller: only for debug purposes, DONT BIND IT
    ///   - success: success completion block
    ///   - failure: failure completion block
    func scanCharacteristics(_ peripheral: CBPeripheral,
                             fromSelectesServices: [CBService]? = nil,
                             specifiedCharacteristics: [CBUUID]? = nil,
                             caller: String = #function,
                             success: @escaping ((BTResponse) -> Void),
                             failure: @escaping ((BTError) -> Void)) {
        
        /// Check services received on params and check characteristics from theirs, else check on
        /// all device services
        if let wrappedServices = fromSelectesServices {
            wrappedServices.forEach({
                peripheral.discoverCharacteristics(specifiedCharacteristics, for: $0)
                self.delegate?.startCharacteristicsScan(peripheral, fromService: $0)
            })
        } else if let wrappedDeviceServices = peripheral.services {
            wrappedDeviceServices.forEach({
                peripheral.discoverCharacteristics(specifiedCharacteristics, for: $0)
                self.delegate?.startCharacteristicsScan(peripheral, fromService: $0)
            })
        } else {
            /// If device doesn't have services and user don't send any service on parameters throw a error
            self.delegate?.managerInterruption(with: .deviceNotReady(#function))
            failure(BTError.unknown)
            return
        }
        
        /// Generate a new pending completion with .discoverCharacteristics operation and discard the result
        _ = self.addPendingCompletion(operation: .discoverCharacteristics,
                                  identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                    peripheral.identifier.uuidString],
                                  completions: (success, failure))
    }
    
    /// Launch a connected Bluetooth device descriptors scan
    ///
    /// - Parameters:
    ///   - peripheral: current peripheral to scan characteristics
    ///   - service: selected service to check descriptors from his characteristics
    ///   - fromSelectedCharacteristics: selected characteristics
    ///   - caller: only for debug purposes, DONT BIND IT
    ///   - success: success completion block
    ///   - failure: failure completion block
    func scanDescriptors(_ peripheral: CBPeripheral,
                         service: CBService? = nil,
                         fromSelectedCharacteristics: [CBCharacteristic]? = nil,
                         caller: String = #function,
                         success: @escaping ((BTResponse) -> Void),
                         failure: @escaping ((BTError) -> Void)) {
        
        /// Check characteristics received on params and check descriptors from theirs, else check on
        /// all device characteristics
        if let wrappedCharacteristics = fromSelectedCharacteristics {
            wrappedCharacteristics.forEach({
                peripheral.discoverDescriptors(for: $0)
                self.delegate?.startDescriptorsScan(peripheral, fromCharacteristic: $0)
            })
        } else if let wrappedDeviceCharacteristics = service?.characteristics {
            wrappedDeviceCharacteristics.forEach({
                peripheral.discoverDescriptors(for: $0)
                self.delegate?.startDescriptorsScan(peripheral, fromCharacteristic: $0)
            })
        } else {
            /// If device doesn't have services/characteristics and user don't send anyone on parameters throw a error
            self.delegate?.managerInterruption(with: .deviceNotReady(#function))
            failure(BTError.unknown)
            return
        }
        
        /// Generate a new pending completion with .discoverDescriptors operation and discard the result
        _ = self.addPendingCompletion(operation: .discoverDescriptors,
                                  identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                    peripheral.identifier.uuidString],
                                  completions: (success, failure))
    }
    
    // MARK: - Bluetooth Connection
    
    /// Connect to a Bluetooth device
    ///
    /// - Parameters:
    ///   - peripheral: device to connect
    ///   - notifyOnConnect: receive a delegate notification on connect to device
    ///   - notifyOnDisconnect: receive a delegate notification on disconnect from device
    ///   - notifyOnUpdate: receive a delegate notification when device is updated
    ///   - caller: only for debug purposes, DONT BIND IT
    ///   - success: success completion block
    ///   - failure: failure completion block
    func connect(_ peripheral: CBPeripheral,
                 notifyOnConnect: Bool = false,
                 notifyOnDisconnect: Bool = false,
                 notifyOnUpdate: Bool = false,
                 caller: String = #function,
                 success: @escaping ((BTResponse) -> Void),
                 failure: @escaping ((BTError) -> Void)) {
        
        self.centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: notifyOnConnect,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: notifyOnDisconnect,
            CBConnectPeripheralOptionNotifyOnNotificationKey: notifyOnUpdate]
        )
        self.delegate?.connecting(peripheral)
        
        /// Generate a new pending completion with .connect operation
        let completion = self.addPendingCompletion(operation: .connect,
                                  identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                    peripheral.identifier.uuidString],
                                  completions: (success, failure))
        
        guard let wrappedCompletion = completion else { return }
        /// Add a expiration block with completion model received
        self.addExpirationBlock(self.buildExpirationOperation(type: .connect, model: wrappedCompletion))
    }
    
    /// Disconnect from a current connected peripheral
    ///
    /// - Parameters:
    ///   - peripheral: current connected peripheral
    ///   - caller: only for debug purposes, DONT BIND IT
    func disconnect(_ peripheral: CBPeripheral, caller: String = #function) {
        
        self.centralManager.cancelPeripheralConnection(peripheral)
        self.delegate?.disconnecting(peripheral)
        
        /// Stop connect pending operations
        self.cancelOperation(with: connectOperationBlockName)
        self.brutalizePendingCompletion(operations: [.connect],
                                        identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                            peripheral.identifier.uuidString])
    }
    
    // MARK: - Subscription
    
    /// Change subscription status for a characteristic
    ///
    /// - Parameters:
    ///   - peripheral: peripheral with characteristics to subscribe
    ///   - selectedCharacteristics: selected characteristics to change subscription
    ///   - caller: only for debug purposes, DONT BIND IT
    func setSubscriptionStatusToCharacteristic(_ peripheral: CBPeripheral,
                                               selectedCharacteristics: [CBCharacteristic]?,
                                               caller: String = #function) {
        selectedCharacteristics?.forEach({
            peripheral.delegate = self
            peripheral.setNotifyValue(true, for: $0)
            
            self.delegate?.settedSubscriptionStatus(peripheral, characteristic: $0, status: true)
            
            /// Generate a new pending completion with .subscription operation and discard the result
            _ = self.addPendingCompletion(operation: .subscription, identifiers: [
                BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString,
                BTSupportedOperation.DescriptibleIdentifiers.characteristicUUID: $0.uuid.uuidString],
                                      completions: nil)
        })
    }
    
    // MARK: - Request
    
    /// Write value on characteristic
    ///
    /// - Parameters:
    ///   - peripheral: peripheral where value gonna be writed
    ///   - characteristic: characteristic  where value gonna be writed
    ///   - value: value to write
    ///   - responseType: write type enumeration
    ///   - caller: only for debug purposes, DONT BIND IT
    ///   - customOperation: completion operation
    ///   - success: success operation block
    ///   - failure: failure operation block
    func writeOnCharacteristic(_ peripheral: CBPeripheral,
                                  characteristic: CBCharacteristic,
                                  value: Data,
                                  responseType: CBCharacteristicWriteType = .withResponse,
                                  caller: String = #function,
                                  customOperation: BTSupportedOperation = .write,
                                  success: @escaping ((BTResponse) -> Void),
                                  failure: @escaping ((BTError) -> Void)) {
        
        peripheral.delegate = self
        peripheral.writeValue(value, for: characteristic, type: responseType)

        self.delegate?.post_requestedCharacteristic(peripheral, characteristic: characteristic, value: value)
        
        /// Generate a new pending completion with customOperation
        let completion = self.addPendingCompletion(operation: customOperation,
                                  identifiers: [
                                    BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                        peripheral.identifier.uuidString,
                                    BTSupportedOperation.DescriptibleIdentifiers.characteristicUUID:
                                        characteristic.uuid.uuidString],
                                  completions: (success, failure))
        
        guard let wrappedCompletion = completion else { return }
        
        /// Add a expiration block with completion model received
        self.addExpirationBlock(self.buildExpirationOperation(type: .write, model: wrappedCompletion))
    }
    
    /// Write value on descriptor
    ///
    /// - Parameters:
    ///   - peripheral: peripheral where value gonna be writed
    ///   - descriptor: descriptor where value gonna be writed
    ///   - value: value to write
    ///   - caller: only for debug purposes, DONT BIND IT
    ///   - customOperation: completion operation
    ///   - success: success operation block
    ///   - failure: failure operation block
    func writeOnDescriptor(_ peripheral: CBPeripheral,
                              descriptor: CBDescriptor,
                              value: Data,
                              caller: String = #function,
                              customOperation: BTSupportedOperation = .write,
                              success: @escaping ((BTResponse) -> Void),
                              failure: @escaping ((BTError) -> Void)) {
        
        peripheral.delegate = self
        peripheral.writeValue(value, for: descriptor)
        
        self.delegate?.post_requestedDescriptor(peripheral, descriptor: descriptor, value: value)
        
        /// Generate a new pending completion with customOperation
        let completion = self.addPendingCompletion(operation: customOperation,
                                  identifiers: [
                                    BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                        peripheral.identifier.uuidString,
                                    BTSupportedOperation.DescriptibleIdentifiers.descriptorUUID:
                                        descriptor.uuid.uuidString],
                                  completions: (success, failure))
        
        guard let wrappedCompletion = completion else { return }
        
        /// Add a expiration block with completion model received
        self.addExpirationBlock(self.buildExpirationOperation(type: .read, model: wrappedCompletion))
    }
    
    /// Read value from characteristic
    ///
    /// - Parameters:
    ///   - peripheral: peripheral where value gonna be readed
    ///   - characteristic: descriptor where value gonna be readed
    ///   - caller: only for debug purposes, DONT BIND IT
    ///   - success: success operation block
    ///   - failure: failure operation block
    func readFromCharacteristic(_ peripheral: CBPeripheral,
                                 characteristic: CBCharacteristic,
                                 caller: String = #function,
                                 success: @escaping ((BTResponse) -> Void),
                                 failure: @escaping ((BTError) -> Void)) {
        
        peripheral.delegate = self
        peripheral.readValue(for: characteristic)
        
        self.delegate?.get_requestedCharacteristic(peripheral, characteristic: characteristic)
        
        /// Generate a new pending completion with updatedValue operation
        let completion = self.addPendingCompletion(operation: .updatedValue,
                                  identifiers: [
                                    BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                        peripheral.identifier.uuidString,
                                    BTSupportedOperation.DescriptibleIdentifiers.characteristicUUID:
                                        characteristic.uuid.uuidString],
                                  completions: (success, failure))
        
        guard let wrappedCompletion = completion else { return }
        
        /// Add a expiration block with completion model received
        self.addExpirationBlock(self.buildExpirationOperation(type: .read, model: wrappedCompletion))
    }
    
    /// Read value from descriptor
    ///
    /// - Parameters:
    ///   - peripheral: peripheral where value gonna be readed
    ///   - descriptor: descriptor where value gonna be readed
    ///   - caller: only for debug purposes, DONT BIND IT
    ///   - success: success operation block
    ///   - failure: failure operation block
    func readFromdescriptor(_ peripheral: CBPeripheral,
                             descriptor: CBDescriptor,
                             caller: String = #function,
                             success: @escaping ((BTResponse) -> Void),
                             failure: @escaping ((BTError) -> Void)) {
        
        peripheral.delegate = self
        peripheral.readValue(for: descriptor)
        
        self.delegate?.get_requestedDescriptor(peripheral, descriptor: descriptor)
        
        /// Generate a new pending completion with updatedValue operation
        let completion = self.addPendingCompletion(operation: .updatedValue,
                                  identifiers: [
                                    BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID:
                                        peripheral.identifier.uuidString,
                                    BTSupportedOperation.DescriptibleIdentifiers.descriptorUUID:
                                        descriptor.uuid.uuidString],
                                  completions: (success, failure))
        
        guard let wrappedCompletion = completion else { return }
        
        /// Add a expiration block with completion model received
        self.addExpirationBlock(self.buildExpirationOperation(type: .read, model: wrappedCompletion))
    }
    
    // MARK: - Debug
    
    /// Print on console the response of a BTResponse
    ///
    /// - Parameter response: response to print on console
    private func response_debugging(_ response: BTResponse) {
        if kBTDebug {
            debugPrint("[- NEW RESPONSE ACTION -]")
            debugPrint("[\(response.getTimeStamp)] DEBUG: -\(self)-: Action \(String(describing: response.getAction).uppercased())")
            debugPrint("[\(response.getTimeStamp)] DEBUG: -\(self)-: Identifiers \(response.getIdentifiers.map({ $0.key.rawValue + $0.value }).joined(separator: " - "))")
            debugPrint("[\(response.getTimeStamp)] DEBUG: -\(self)-: Value \(String(describing: response.getValue))")
            debugPrint("[\(response.getTimeStamp)] DEBUG: -\(self)-: Error \(String(describing: response.getError?.localizedDescription))")
            debugPrint("[--------------]")
        }
    }
    
    // MARK: - Completion Managing
    
    /// Check completionModel and handle the response using model completions
    ///
    /// - Parameters:
    ///   - model: Completion model to handle
    ///   - successData: value to bind success completion block
    ///   - error: value to bind failure completion block
    private func manageCompletion(model: BTMCompletionModel, successData: Any?, error: BTError?) {
        /// Create a operation to force kill pending completion when all data is received
        let finalizeTaskOperation: Operation = Operation()
        finalizeTaskOperation.completionBlock = {
            self.brutalizePendingCompletion(model: model)
        }
        
        let response = BTResponse.init(action: model.action,
                                        identifiers: model.identifiers,
                                        value: successData,
                                        error: error,
                                        finalizeOperation: finalizeTaskOperation)
        
        if let wrappedError = error {
            model.getCallbacks().1(wrappedError)
        } else {
            model.getCallbacks().0(response)
        }
        self.response_debugging(response)
    }
    
    /// Add completion to model to pending array
    ///
    /// - Parameters:
    ///   - operation: bluetooth operation for completion
    ///   - identifiers: identifiers for completion
    ///   - completions: completions tuple for response
    /// - Returns: completion model
    private func addPendingCompletion(operation: BTSupportedOperation,
                                      identifiers: [BTSupportedOperation.DescriptibleIdentifiers: String],
                                      completions: (((BTResponse) -> Void), ((BTError) -> Void))?
        ) -> BTMCompletionModel? {
        
        /// Is mandatory attach completions
        guard let wrappedcompletions = completions else { return nil }
        
        let newCompletion = BTMCompletionModel.init(action: operation,
                                                           identifiers: identifiers,
                                                           success: wrappedcompletions.0,
                                                           failure: wrappedcompletions.1)
        
        /// Find other completions with similar characteristics
        let match = self.fetchLastPendingcompletion(operation: operation, identifiers: identifiers)
        
        if let wrappedMatch = match,
            let index: Int = self.pendingCompletions.firstIndex(of: wrappedMatch) {
            self.pendingCompletions[index] = newCompletion
            
        } else {
            self.pendingCompletions.append(newCompletion)
        }
        return newCompletion
    }
    
    /// Find and force to remove all pending operations with same operations and identifiers getted by parameter
    ///
    /// - Parameters:
    ///   - operations: bluetooth operations array
    ///   - identifiers: identifiers array
    private func brutalizePendingCompletion(operations: [BTSupportedOperation],
                                            identifiers: [BTSupportedOperation.DescriptibleIdentifiers: String]?) {
        
        operations.forEach({
            guard let operationMatch = self.fetchAllPendingCompletions(operation: $0, identifiers: identifiers).first,
                let index = self.pendingCompletions.firstIndex(of: operationMatch) else { return }
            
            self.pendingCompletions.remove(at: index)
        })
    }
    
    /// Find and force to remove all pending operations with same model getted by parameter
    ///
    /// - Parameter model: completion model
    private func brutalizePendingCompletion(model: BTMCompletionModel) {
        guard let operationMatch = self.pendingCompletions.filter({ $0 == model}).first,
            let index = self.pendingCompletions.firstIndex(of: operationMatch) else { return }
        
        self.pendingCompletions.remove(at: index)
    }
    
    /// Find and return first completion model with same operation and identifiers
    ///
    /// - Parameters:
    ///   - operation: supported operation
    ///   - identifiers: identifiers array
    /// - Returns: completion model
    private func fetchLastPendingcompletion(operation: BTSupportedOperation,
                                        identifiers: [BTSupportedOperation.DescriptibleIdentifiers: String]) -> BTMCompletionModel? {
        let matches = self.fetchAllPendingCompletions(operation: operation, identifiers: identifiers)
        guard !matches.isEmpty else { return nil }
        return matches.last
    }
    
    /// Deep matching, checking operation and identifiers getted by parameter
    ///
    /// - Parameters:
    ///   - operation: supported operation
    ///   - identifiers: identifiers array
    /// - Returns: completion models array
    private func fetchAllPendingCompletions(operation: BTSupportedOperation,
                                   identifiers: [BTSupportedOperation.DescriptibleIdentifiers: String]?) -> [BTMCompletionModel] {
        guard !self.pendingCompletions.isEmpty else { return [] }
        
        /// Filter completion models by operation
        var matches = self.pendingCompletions.filter({ pendingElement in
            pendingElement.action == operation
        })
        
        /// Filter by identifiers key and value
        if let wrappedIdentifiers = identifiers {
            matches = matches.filter({
                if !wrappedIdentifiers.isEmpty {
                    return $0.identifiers.contains(where: { pendingIdentifier in
                        wrappedIdentifiers.keys.contains(pendingIdentifier.key) &&
                            wrappedIdentifiers.values.contains(pendingIdentifier.value)
                    })
                } else {
                    return $0.identifiers.isEmpty
                }
            })
        }
        return matches
    }
    
    // MARK: - Expiration Operations
    
    /// Create a expiration operation block for operation queue
    ///
    /// - Parameters:
    ///   - type: supported operation
    ///   - peripheral: peripheral to connect
    ///   - model: completion model
    /// - Returns: operation block with expiration code
    private func buildExpirationOperation(type: BTSupportedOperation,
                                          peripheral: CBPeripheral? = nil,
                                          model: BTMCompletionModel) -> BlockOperation {
        let stopOperation = BlockOperation()
        
        switch type {
        case .scan:
            stopOperation.addExecutionBlock {
                Thread.sleep(forTimeInterval: type.timeOut)
                guard !stopOperation.isCancelled else { return }
                self.stopScanDevices()
                model.getCallbacks().1(BTError.timeOut)
                self.brutalizePendingCompletion(model: model)
            }
            stopOperation.name = scanOperationBlockName

        case .connect:
            stopOperation.addExecutionBlock {
                Thread.sleep(forTimeInterval: type.timeOut)
                guard !stopOperation.isCancelled else { return }
                if let wrappedPeripheral = peripheral {
                    self.disconnect(wrappedPeripheral)
                }
                model.getCallbacks().1(BTError.timeOut)
                self.brutalizePendingCompletion(model: model)
            }
            stopOperation.name = connectOperationBlockName

        case .write:
            stopOperation.addExecutionBlock {
                Thread.sleep(forTimeInterval: type.timeOut)
                guard !stopOperation.isCancelled else { return }
                model.getCallbacks().1(BTError.timeOut)
                self.brutalizePendingCompletion(model: model)
            }
            stopOperation.name = writeOperationBlockName

        case .read:
            stopOperation.addExecutionBlock {
                Thread.sleep(forTimeInterval: type.timeOut)
                guard !stopOperation.isCancelled else { return }
                model.getCallbacks().1(BTError.timeOut)
                self.brutalizePendingCompletion(model: model)
            }
            stopOperation.name = readOperationBlockName
        default:
            break
        }
        
        return stopOperation
    }
    
    /// Add expiration block to queue
    ///
    /// - Parameter operation: operation block
    private func addExpirationBlock(_ operation: BlockOperation) {
        self.cancelOperation(with: operation.name)
        self.addOperation(operation: operation)
    }
    
    /// Cancel operation block from queue with his name
    ///
    /// - Parameter name: operation name
    private func cancelOperation(with name: String?) {
        guard let wrappedName = name else { return }
        
        self.bluetoothOperationsQueue.operations.filter({
            $0.name != nil && $0.name! == wrappedName
        }).forEach({
            $0.cancel()
        })
    }
}

extension FDABluetoothManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK: - CentralManager Delegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.delegate?.centralManagerDidChangeState(central.state)
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        peripheral.delegate = self
        self.deviceManager.append(peripheral)
        self.delegate?.newDeviceFounded(peripheral, advertisementData: advertisementData, rssi: RSSI)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .scan,
                                                          identifiers: [:]) {
            self.manageCompletion(model: wrappedModel, successData: peripheral, error: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.delegate?.connectedToDevice(peripheral)
        self.cancelOperation(with: connectOperationBlockName)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .connect,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            
            self.manageCompletion(model: wrappedModel, successData: true, error: nil)
            self.cancelOperation(with: connectOperationBlockName)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let parsedError = error != nil ? BTError.errorOnConnection(error!.localizedDescription) : nil
        self.delegate?.failToConnectToDevice(peripheral, error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .connect,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: false, error: parsedError)
            self.cancelOperation(with: connectOperationBlockName)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let parsedError = error != nil ? BTError.errorOnConnection(error!.localizedDescription) : nil
        self.delegate?.disconnecting(peripheral)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .disconnect,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: false, error: parsedError)
            self.cancelOperation(with: connectOperationBlockName)
        }
    }
    
    // MARK: - CBPeripheral Delegate
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let parsedError = error != nil ? BTError.errorOnRSSI(error!.localizedDescription) : nil
        self.delegate?.readedRSSI(peripheral,
                                  rssi: RSSI,
                                  error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .read,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: peripheral, error: parsedError)
            self.cancelOperation(with: readOperationBlockName)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let parsedError = error != nil ? BTError.errorOnServices(error!.localizedDescription) : nil
        self.delegate?.discoveredServices(peripheral, services: peripheral.services, error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .discoverServices,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: peripheral.services, error: parsedError)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let parsedError = error != nil ? BTError.errorOnCharacteristics(error!.localizedDescription) : nil
        self.delegate?.discoveredCharacteristics(peripheral,
                                                 characteristics: service.characteristics,
                                                 error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .discoverCharacteristics,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString,
                                                                        BTSupportedOperation.DescriptibleIdentifiers.serviceUUID: service.uuid.uuidString]) {
            self.setSubscriptionStatusToCharacteristic(peripheral, selectedCharacteristics: service.characteristics)
            self.manageCompletion(model: wrappedModel, successData: service.characteristics, error: parsedError)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverDescriptorsFor characteristic: CBCharacteristic,
                    error: Error?) {
        let parsedError = error != nil ? BTError.errorOnDescriptors(error!.localizedDescription) : nil
        self.delegate?.discoveredDescriptors(peripheral, descriptors: characteristic.descriptors, error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .discoverDescriptors,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.characteristicUUID: characteristic.uuid.uuidString,
                                                                        BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: characteristic.descriptors, error: parsedError)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let parsedError = error != nil ? BTError.errorOnCharacteristics(error!.localizedDescription) : nil
        self.delegate?.updatedValueForCharacteristic(peripheral, characteristic: characteristic, error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .updatedValue,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.characteristicUUID: characteristic.uuid.uuidString,
                                                                        BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: characteristic.value, error: parsedError)
            self.cancelOperation(with: writeOperationBlockName)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        let parsedError = error != nil ? BTError.errorOnDescriptors(error!.localizedDescription) : nil
        self.delegate?.updatedValueForDescriptor(peripheral, descriptor: descriptor, error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .updatedValue,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.descriptorUUID: descriptor.uuid.uuidString,
                                                                        BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: descriptor.value, error: parsedError)
            self.cancelOperation(with: writeOperationBlockName)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        let parsedError = error != nil ? BTError.errorOnCharacteristics(error!.localizedDescription) : nil
        self.delegate?.updateNotificationReceived(peripheral, characteristic: characteristic, error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .subscription,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.characteristicUUID: characteristic.uuid.uuidString,
                                                                        BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: characteristic.value, error: parsedError)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let parsedError = error != nil ? BTError.errorOnCharacteristics(error!.localizedDescription) : nil
        self.delegate?.writedValueOnCharacteristic(peripheral, characteristic: characteristic, error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .write,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString,
                                                                         BTSupportedOperation.DescriptibleIdentifiers.characteristicUUID: characteristic.uuid.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: characteristic.value, error: parsedError)
            self.cancelOperation(with: writeOperationBlockName)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        let parsedError = error != nil ? BTError.errorOnDescriptors(error!.localizedDescription) : nil
        self.delegate?.writedValueOnDescriptor(peripheral, descriptor: descriptor, error: parsedError)
        
        /// Check completion model and handle it with manageCompletion
        if let wrappedModel = self.fetchLastPendingcompletion(operation: .write,
                                                          identifiers: [BTSupportedOperation.DescriptibleIdentifiers.peripheralUUID: peripheral.identifier.uuidString,
                                                                        BTSupportedOperation.DescriptibleIdentifiers.descriptorUUID: descriptor.uuid.uuidString]) {
            self.manageCompletion(model: wrappedModel, successData: descriptor.value, error: parsedError)
            self.cancelOperation(with: writeOperationBlockName)
        }
    }
    
    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        self.delegate?.peripheralNameHasChanged(peripheral)
    }
}

protocol FDABluetoothManagerDelegate: class {
    func startScan()
    func stopScan()
    func connecting(_ peripheral: CBPeripheral)
    func disconnecting(_ peripheral: CBPeripheral)
    func startServicesScan(_ peripheral: CBPeripheral, services: [CBUUID]?)
    func startCharacteristicsScan(_ peripheral: CBPeripheral, fromService: CBService)
    func startDescriptorsScan(_ peripheral: CBPeripheral, fromCharacteristic: CBCharacteristic)
    func settedSubscriptionStatus(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, status: Bool)
    func post_requestedCharacteristic(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, value: Data)
    func post_requestedDescriptor(_ peripheral: CBPeripheral, descriptor: CBDescriptor, value: Data)
    func get_requestedCharacteristic(_ peripheral: CBPeripheral, characteristic: CBCharacteristic)
    func get_requestedDescriptor(_ peripheral: CBPeripheral, descriptor: CBDescriptor)
    
    func centralManagerDidChangeState(_ state: CBManagerState)
    func newDeviceFounded(_ peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)
    func connectedToDevice(_ peripheral: CBPeripheral)
    func disconnectedFromDevice(peripheral: CBPeripheral)
    func failToConnectToDevice(_ peripheral: CBPeripheral, error: BTError?)
    func willRestoreState(dict: [String: Any])
    
    func readedRSSI(_ peripheral: CBPeripheral, rssi: NSNumber, error: BTError?)
    func discoveredServices(_ peripheral: CBPeripheral, services: [CBService]?, error: BTError?)
    func discoveredCharacteristics(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]?, error: BTError?)
    func discoveredDescriptors(_ peripheral: CBPeripheral, descriptors: [CBDescriptor]?, error: BTError?)
    func updatedValueForCharacteristic(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: BTError?)
    func updatedValueForDescriptor(_ peripheral: CBPeripheral, descriptor: CBDescriptor, error: BTError?)
    func updateNotificationReceived(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: BTError?)
    func writedValueOnCharacteristic(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: BTError?)
    func writedValueOnDescriptor(_ peripheral: CBPeripheral, descriptor: CBDescriptor, error: BTError?)
    func peripheralNameHasChanged(_ peripheral: CBPeripheral)
    
    func managerInterruption(with error: BTError)
}

extension FDABluetoothManagerDelegate {
    func startScan() {}
    func stopScan() {}
    func connecting(_ peripheral: CBPeripheral) {}
    func disconnecting(_ peripheral: CBPeripheral) {}
    func startServicesScan(_ peripheral: CBPeripheral, services: [CBUUID]?) {}
    func startCharacteristicsScan(_ peripheral: CBPeripheral, fromService: CBService) {}
    func startDescriptorsScan(_ peripheral: CBPeripheral, fromCharacteristic: CBCharacteristic) {}
    func settedSubscriptionStatus(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, status: Bool) {}
    func post_requestedCharacteristic(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, value: Data) {}
    func post_requestedDescriptor(_ peripheral: CBPeripheral, descriptor: CBDescriptor, value: Data) {}
    func get_requestedCharacteristic(_ peripheral: CBPeripheral, characteristic: CBCharacteristic) {}
    func get_requestedDescriptor(_ peripheral: CBPeripheral, descriptor: CBDescriptor) {}
    
    func newDeviceFounded(_ peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {}
    func connectedToDevice(_ peripheral: CBPeripheral) {}
    func disconnectedFromDevice(peripheral: CBPeripheral) {}
    func failToConnectToDevice(_ peripheral: CBPeripheral, error: BTError?) {}
    func willRestoreState(dict: [String: Any]) {}
    
    func readedRSSI(_ peripheral: CBPeripheral, rssi: NSNumber, error: BTError?) {}
    func discoveredServices(_ peripheral: CBPeripheral, services: [CBService]?, error: BTError?) {}
    func discoveredCharacteristics(_ peripheral: CBPeripheral,
                                   characteristics: [CBCharacteristic]?,
                                   error: BTError?) {}
    func discoveredDescriptors(_ peripheral: CBPeripheral, descriptors: [CBDescriptor]?, error: BTError?) {}
    func updatedValueForCharacteristic(_ peripheral: CBPeripheral,
                                       characteristic: CBCharacteristic,
                                       error: BTError?) {}
    func updatedValueForDescriptor(_ peripheral: CBPeripheral, descriptor: CBDescriptor, error: BTError?) {}
    func updateNotificationReceived(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: BTError?) {}
    func writedValueOnCharacteristic(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: BTError?) {}
    func writedValueOnDescriptor(_ peripheral: CBPeripheral, descriptor: CBDescriptor, error: BTError?) {}
    func peripheralNameHasChanged(_ peripheral: CBPeripheral) {}
    
    func managerInterruption(with error: BTError) {}
}
