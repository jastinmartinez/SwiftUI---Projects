//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import FluentKit

struct MeasureUnitMigration: Migration {
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("MeasureUnit")
            .delete()
    }
    
    func prepare(on database: Database) -> EventLoopFuture<Void> {
         
        database.schema("MeasureUnit")
            .field("MeasureUnitID",.int,.required,.identifier(auto: true))
            .field("MeasureUnitDescription",.string,.required)
            .field("MeasureUnitState",.bool,.required)
            .create()
    }
}
