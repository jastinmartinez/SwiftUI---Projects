//
//  UserInfo.swift
//  Purchase
//
//  Created by Jastin on 9/12/21.
//

import Foundation
import Realm
import RealmSwift

class UserInfo: Object {
    
    @Persisted var key: String?
    
    @Persisted var id: Int?
    
    @Persisted var email: String?
    
    @Persisted var name: String?
    
    convenience init(key: String, user: User) {
        
        self.init()
        
        self.key = key
        
        self.id = user.id
        
        self.email = user.email
        
        self.name = user.name
    }
}
