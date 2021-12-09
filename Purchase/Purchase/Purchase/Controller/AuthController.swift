//
//  AuthController.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation

class AuthController : ObservableObject  {
    
    func authenticateSignUp(_ model: User.SignUp, completion: @escaping (Bool) -> () ) {
        
        AuthAPIService<User.SignUp>(apiResource: .SignUp).create(model: model) { user in
            
            if user.id != nil {
                
                UserHelper().saveUser(user: user, withPassword: model.password)
            }
            completion(user.id != nil)
        }
    }
    
    func authenticateSignIn(_ model: User.SignIn, completion: @escaping (Bool) -> () ) {
        
        AuthAPIService<User.SignIn>(apiResource: .SignIn).create(model: model) { user in
            
            completion(user.id != nil)
            
        }
    }
}
