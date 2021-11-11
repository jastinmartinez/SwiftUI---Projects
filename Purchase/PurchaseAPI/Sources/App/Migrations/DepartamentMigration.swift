//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import FluentKit

struct DepartamentMigration: Migration {
  
    func revert(on database: Database) -> EventLoopFuture<Void> {
         database.schema("Department")
            .delete()
    }
    
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        
        return database.schema("Department")
            .field("DepartmentID",.int,.required,.identifier(auto: true))
            .field("DepartmentName",.string,.required)
            .field("DepartmentState",.bool,.required)
            .create()
    }
}
