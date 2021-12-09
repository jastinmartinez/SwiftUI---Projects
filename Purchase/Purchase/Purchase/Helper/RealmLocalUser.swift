//
//  LocalUser.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation
import RealmSwift

final class RealmLocalUser {
    
    private var dbRealm: Realm
    
    init () {
        
        self.dbRealm = try! Realm()
    }
    

    func getUser() -> UserInfo? {
        
        return dbRealm.objects(UserInfo.self).first
    }
    
    func saveUser(user: User, withPassword: String) {
        
        let userFromDb = dbRealm.objects(UserInfo.self)
        
        if userFromDb.count > 0 {
            
            dbRealm.delete(userFromDb)
        }
        
        let userKey = "\(Data("\(user.email):\(withPassword)".utf8).base64EncodedString())"
        
        let userInfo = UserInfo(key: userKey, user: user)
        
        try! dbRealm.write {
            
            dbRealm.add(userInfo)
            
        }
    }
}
