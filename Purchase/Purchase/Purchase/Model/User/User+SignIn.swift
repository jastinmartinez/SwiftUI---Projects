//
//  User+SignIn.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import Foundation

extension User {
    
    struct SignIn: Codable {
        
        var email: String
        
        var password:String
    }
}
