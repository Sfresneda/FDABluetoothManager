//
//  Constants.swift
//  FDABluetoothManagerExample
//
//  Created by Sergio Fresneda on 12/28/19.
//  Copyright © 2019 Sergio Fresneda. All rights reserved.
//

import Foundation

// MARK: - Target Bluetooth Info
enum TargetBluetoothDevice {
    enum Services: String, CaseIterable {
        case example = ""
    }
    enum Characteristics: String, CaseIterable {
        case example = ""
    }
    enum Descriptors: String, CaseIterable {
        case example = ""
    }
}

let scanOperationBlockName: String = "scanOperationBlock"
let connectOperationBlockName: String = "connectOperationBlock"
let writeOperationBlockName: String = "writeOperationBlock"
let readOperationBlockName: String = "readOperationBlock"

let kBTQueueName: String = "btQueue"

let kBTDebug: Bool = false
