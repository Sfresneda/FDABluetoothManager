//
//  BTMCompletionModel.swift
//
//  Created by Sergio Fresneda on 12/28/19.
//  Copyright © 2019 Sergio Fresneda. All rights reserved.
//

import Foundation

/// Bluetooth Supported Operations
///
/// - scan: Scan devices
/// - read: Read value from device
/// - write: Write value to device
/// - connect: Connect to device
/// - disconnect: Disconnect from device
/// - discoverServices: Discover services from device
/// - discoverCharacteristics: Discover characteristics from service
/// - discoverDescriptors: Discover descriptors from characteristic
/// - updatedValue: Device update value
/// - subscription: Subscription updated
/// - state: Bluetooth state
enum BTSupportedOperation {
    case scan
    case read
    case write
    case connect
    case disconnect
    case discoverServices
    case discoverCharacteristics
    case discoverDescriptors
    case updatedValue
    case subscription
    case state
    
    /// Descriptible Identifiers
    ///
    /// - peripheralUUID: peripheral identifier UUID
    /// - peripheralName: peripheral name
    /// - peripheralRSSI: peripheral rssi
    /// - peripheralAdvertisementData: peripheral advertisement
    /// - serviceUUID: services identifier UUID
    /// - characteristicUUID: characteristic identifier UUID
    /// - characteristicValue: characteristic value
    /// - descriptorUUID: descriptor identifier UUID
    /// - descriptorValue: descriptor value
    /// - centralManagerState: central manager state
    enum DescriptibleIdentifiers: String {
        case peripheralUUID = "peripheralUUID"
        case peripheralName = "peripheralName"
        case peripheralRSSI = "peripheralRSSI"
        case peripheralAdvertisementData = "peripheralAdvertisement"
        case serviceUUID = "serviceUUID"
        case characteristicUUID = "characteristicUUID"
        case characteristicValue = "characteristicValue"
        case descriptorUUID = "descriptorUUID"
        case descriptorValue = "descriptorValue"
        case centralManagerState = "centralManagerState"
    }
    
    /// Expiration timeout
    var timeOut: TimeInterval {
        switch self {
        case .scan:
            return 10
        case .read:
            return 2
        case .write:
            return 30
        case .connect:
            return 3
        case .disconnect:
            return 1
        case .discoverServices:
            return 2
        case .discoverCharacteristics:
            return 2
        case .discoverDescriptors:
            return 2
        case .updatedValue:
            return 30
        case .subscription:
            return 20
        case .state:
            return 50
        }
    }
}

/// Bluetooth Manager Completion Model
class BTMCompletionModel: NSObject {
    var action: BTSupportedOperation
    var identifiers: [BTSupportedOperation.DescriptibleIdentifiers: String]
    
    private var successCallback: ((BTResponse) -> Void)
    private var failureCallback: ((BTError) -> Void)
    private var isCancelable: Bool = true
    
    init(action: BTSupportedOperation,
         identifiers: [BTSupportedOperation.DescriptibleIdentifiers: String],
         success: @escaping ((BTResponse) -> Void),
         failure: @escaping ((BTError) -> Void)) {
        
        self.action = action
        self.identifiers = identifiers
        self.successCallback = success
        self.failureCallback = failure
        
        super.init()
    }
    
    /// Return callbacks
    ///
    /// - Returns: tuple of callbacks (success, failure)
    func getCallbacks() -> ((((BTResponse) -> Void), ((BTError) -> Void))) {
        self.isCancelable = false
        return (self.successCallback, self.failureCallback)
    }
}
