//
//  Item.swift
//  Luno
//
//  Created by Farin Altenhöner on 04.08.25.
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
