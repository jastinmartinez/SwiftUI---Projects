//
//  LocalUser.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation
import RealmSwift
import Realm



final class UserHelper {
    
    private var dbRealm: Realm = RealmHelper.shared
    
    static var userInfo: UserInfo? = {
        
        let instance = RealmHelper.shared.objects(UserInfo.self).first
        
        return instance
    }()
    
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
