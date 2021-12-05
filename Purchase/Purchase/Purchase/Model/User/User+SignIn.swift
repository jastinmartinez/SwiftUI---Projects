//
//  User+SignIn.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import Foundation

extension User {
    
    struct SignIn: Encodable {
        
        var email: String
        
        var password:String
    }
}
