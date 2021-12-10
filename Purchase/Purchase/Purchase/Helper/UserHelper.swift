//
//  LocalUser.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation
import RealmSwift
import Realm
import SwiftUI



final class UserHelper  {
    
    private let realmDb = RealmHelper.shared
    
     var userInfo: UserInfo? = {
        
        return RealmHelper.shared.objects(UserInfo.self).last
        
    }()
    
    func removeUser() {
        
        try! realmDb.write {
            
            realmDb.delete(RealmHelper.shared.objects(UserInfo.self))
        }
    }
    
    func temporaryUserInfoHolder(user: User.SignIn) {
        
        removeUser()
    
        let userKey = "\(Data("\(user.email):\(user.password)".utf8).base64EncodedString())"
        
        let userInfo = UserInfo(key: userKey, user: User(id: nil, name: "Temporal", email: user.email, passwordHash: ""))
        
        try! realmDb.write {
            
            realmDb.add(userInfo)
        }
    }
    
    func saveUser(user: User, withPassword: String) {
        
        removeUser()
        
        let userKey = "\(Data("\(user.email):\(withPassword)".utf8).base64EncodedString())"
        
        let userInfo = UserInfo(key: userKey, user: user)
        
        try! realmDb.write {
            
            realmDb.add(userInfo)
        }
    }
}
