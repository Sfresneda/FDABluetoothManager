//
//  BTError.swift
//
//  Created by Sergio Fresneda on 12/28/19.
//  Copyright © 2019 Sergio Fresneda. All rights reserved.
//

import Foundation

enum BTError {
    case managerNotReady
    case btNotReady
    case btIsBusy
    case deviceNotReady(String)
    case errorOnConnection(String)
    case errorOnServices(String)
    case errorOnCharacteristics(String)
    case errorOnDescriptors(String)
    case errorOnRSSI(String)
    case timeOut
    case unknown
    
    var errorCode: Int {
        switch self {
        case .managerNotReady:
            return 314
        case .btNotReady:
            return 315
        case .btIsBusy:
            return 316
        case .deviceNotReady:
            return 317
        case .errorOnConnection:
            return 318
        case .errorOnServices:
            return 319
        case .errorOnCharacteristics:
            return 320
        case .errorOnDescriptors:
            return 321
        case .errorOnRSSI:
            return 322
        case .timeOut:
            return 415
        case .unknown:
            return 420
        }
    }
    var localizedDescription: String {
        switch self {
        case .managerNotReady:
            return "_error_bluetooth_manager_not_ready_description"
        case .btNotReady:
            return "_error_bluetooth_ble_not_ready_description"
        case .btIsBusy:
            return "_error_bluetooth_ble_is_busy_description"
        case .deviceNotReady(let function):
            return "_error_bluetooth_device_not_ready_description" + function
        case .errorOnConnection(let description):
            return description
        case .errorOnServices(let description):
            return description
        case .errorOnCharacteristics(let description):
            return description
        case .errorOnDescriptors(let description):
            return description
        case .errorOnRSSI(let description):
            return description
        case .timeOut:
            return "_error_bluetooth_timeOut_description"
        case .unknown:
            return "_error_bluetooth_unknown_description"
        }
    }
}
