//
//  RealmHelper.swift
//  Purchase
//
//  Created by Jastin on 9/12/21.
//

import Foundation
import RealmSwift

class RealmHelper {
    
    static var shared: Realm = {
        
        let instance = try! Realm()
        
        return instance
    }()
}
