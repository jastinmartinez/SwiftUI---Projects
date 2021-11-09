//
//  BoolToString.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import Foundation

extension Bool {
    
    func toString() -> String {
        
        return self ? "Active" : "Inactive"
    }
}
