//
//  Profile+Date.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Database/Profile+Date.swift.
//

import Foundation

public extension Date {
    var myFormat: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateFormatter.string(from: self)
    }
}
