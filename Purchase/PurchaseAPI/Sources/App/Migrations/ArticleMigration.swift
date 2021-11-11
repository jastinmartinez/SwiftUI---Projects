//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import FluentKit

struct ArticleMigration: Migration {
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        
        database.schema("Article").delete()
    }
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        
        database.schema("Article")
            .field("ArticleID",.int,.required,.identifier(auto: true))
            .field("ArticleDescription",.string,.required)
            .field("ArticleMark",.string,.required)
            .field("ArticleMeasureUnitID",.int,.required,.references("MeasureUnit", "MeasureUnitID"))
            .field("ArticleStock",.double,.required)
            .field("ArticleState",.bool,.required)
            .create()
        
    }
}
