//
//  File.swift
//  
//
//  Created by Jastin on 27/11/21.
//

import Foundation

import FluentKit

extension User {
    
    struct UserMigration: Migration {
        
        func prepare(on database: Database) -> EventLoopFuture<Void>   {
            
             database.schema("Users")
                .field("UserID",.int,.required,.identifier(auto: true))
                .field("UserName",.string,.required)
                .field("UserEmail",.string,.required)
                .field("UserPasswordHash",.string,.required)
                .unique(on: "UserEmail")
                .create()
                
        }
        
        func revert(on database: Database) -> EventLoopFuture<Void>    {
            
            database.schema("Users").delete()
        }
    }
}
