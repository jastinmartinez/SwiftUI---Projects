//
//  AuthController.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation

class AuthController : ObservableObject  {
    
    func registerUsingEmailAndPassword(_ model: User.SignUp, completion: @escaping (Bool) -> () ) {
    
        AuthAPIService<User.SignUp>(apiResource: .SignUp).create(model: model) { user in
            
            if user.id != nil {
                
                UserHelper().saveUser(user: user, withPassword: model.password)
            }
            completion(user.id != nil)
        }
    }
    
    func authenticateUsingEmailAndPassword(_ model: User.SignIn, completion: @escaping (Bool) -> () ) {
        
        UserHelper().temporaryUserInfoHolder(user: model)
        
        AuthAPIService<User.SignIn>(apiResource: .SignIn).create(model: model) { user in
            
            if user.id != nil {
                
                UserHelper().saveUser(user: user, withPassword: model.password)
                
            }
            
            completion(user.id != nil)
            
        }
    }
}
