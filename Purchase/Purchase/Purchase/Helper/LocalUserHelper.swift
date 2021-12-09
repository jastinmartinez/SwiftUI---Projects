//
//  LocalUser.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation

final class LocalUserHelper {
    

    func getUser() -> User? {
        
        guard let jsonUser =  UserDefaults.standard.data(forKey: "userInfo") else { return nil }
        
        guard let user = try? JSONDecoder().decode(User.self, from: jsonUser) else {  return nil }
                             
        return  user
    }
    
    func saveUser(user: User, withPassword: String) {
        
        guard let userToJson = try?  JSONEncoder().encode(user) else { return }
        
        
        //userDefaults.setValue(userToJson, forKey: "userInfo")
        UserDefaults.standard.set("a", forKey: "userKey1")
        UserDefaults.standard.setValue("\(Data("\(user.email):\(withPassword)".utf8).base64EncodedString())", forKey: "userKey")
        
        UserDefaults.standard.synchronize()
        
        print(UserDefaults.standard.bool(forKey: "userKey"))
        print(UserDefaults.standard.bool(forKey: "userKey1"))
        
    }
}
