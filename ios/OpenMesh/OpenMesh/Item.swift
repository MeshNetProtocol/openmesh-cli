//
//  Item.swift
//  OpenMesh
//
//  Created by wesley on 2026/1/8.
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
