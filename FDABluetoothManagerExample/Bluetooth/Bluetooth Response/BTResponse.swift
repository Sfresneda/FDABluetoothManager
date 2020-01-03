//
//  BTResponse.swift
//
//  Created by Sergio Fresneda on 12/28/19.
//  Copyright © 2019 Sergio Fresneda. All rights reserved.
//

import Foundation
import CoreBluetooth

/// Bluetooth Response
class BTResponse: NSObject {
    private var timeStamp: TimeInterval
    private var action: BTSupportedOperation
    private var identifiers: [BTSupportedOperation.DescriptibleIdentifiers: String]?
    private var value: Any?
    private var error: BTError?
    private var finalizeOperationFunction: Operation?
    
    init(action: BTSupportedOperation,
         identifiers: [BTSupportedOperation.DescriptibleIdentifiers: String]?,
         value: Any?,
         error: BTError?,
         finalizeOperation: Operation? = nil) {
        
        self.timeStamp = Date().timeIntervalSince1970
        self.action = action
        self.identifiers = identifiers
        self.value = value
        self.error = error
        self.finalizeOperationFunction = finalizeOperation
    }
    var getTimeStamp: TimeInterval {
        return self.timeStamp
    }
    var getAction: BTSupportedOperation {
        return self.action
    }
    var getIdentifiers: [BTSupportedOperation.DescriptibleIdentifiers: String] {
        return self.identifiers ?? [:]
    }
    var getValue: Any? {
        return self.value
    }
    var getError: BTError? {
        return self.error
    }
    
    /// Launch finish operation
    func finishOperation() {
        guard let wrappedOperation = self.finalizeOperationFunction else { return }
        wrappedOperation.start()
    }
}
