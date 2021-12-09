//
//  File.swift
//  
//
//  Created by Jastin on 27/11/21.
//

import Foundation
import Fluent
import Vapor

extension User: ModelAuthenticatable {
    
    static let usernameKey = \User.$email
    
    static let passwordHashKey = \User.$passwordHash
    
    func verify(password: String) throws -> Bool {
        
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}
