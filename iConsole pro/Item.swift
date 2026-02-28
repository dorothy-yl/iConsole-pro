//
//  Item.swift
//  iConsole pro
//
//  Created by BoShan on 2026/2/27.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
