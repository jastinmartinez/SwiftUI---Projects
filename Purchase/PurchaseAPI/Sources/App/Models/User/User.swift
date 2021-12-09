//
//  File.swift
//  
//
//  Created by Jastin on 27/11/21.
//

import Foundation
import Vapor

final class User: DbModel {
    
    static var schema: String = "Users"
    
    @ID(custom: "UserID", generatedBy: .database)
    var id: Int?
    
    @Field(key: "UserName")
    var name: String
    
    @Field(key: "UserEmail")
    var email: String
    
    @Field(key: "UserPasswordHash")
    var passwordHash: String
    
    init () {}
    
    init(id: Int? = nil, name: String, email: String, passwordHash: String)
    {
        self.id = id
        self.name = name
        self.email = email
        self.passwordHash = passwordHash
    }
}




