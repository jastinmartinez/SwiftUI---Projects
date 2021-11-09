//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import FluentKit


struct ProviderMigration: Migration {
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        
        database.schema("Provider")
            .delete()
    }

    func prepare(on database: Database) -> EventLoopFuture<Void> {
        
        database.schema("Provider")
            .field("ProviderID",.int,.required,.identifier(auto: true))
            .field("ProviderPersonID",.string,.required)
            .field("ProviderComercialName",.string,.required)
            .field("ProviderState",.bool,.required)
            .create()
    }
}
