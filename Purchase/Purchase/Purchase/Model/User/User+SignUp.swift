//
//  User+SignUp.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import Foundation

extension User {

    struct SignUp: Encodable {
        
        var name: String
        
        var email: String
        
        var password: String
        
        var confirmPassword: String
    }
}
