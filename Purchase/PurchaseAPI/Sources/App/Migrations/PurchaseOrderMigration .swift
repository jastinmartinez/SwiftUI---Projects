//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import FluentKit

struct PurchaseOrderMigration: Migration {
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("PurchaseOrder")
            .delete()
    }
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        database.schema("PurchaseOrder")
            .field("PurchaseOrderID",.int,.required,.identifier(auto: true))
            .field("PurchaseOrderNumber",.string,.required)
            .field("PurchaseOrderDate",.string,.required)
            .field("PurchaseOrderArticleID",.int,.required,.references("Article", "ArticleID"))
            .field("PurchaseOrderQuantity",.double,.required)
            .field("PurchaseOrderMeasureUnitID",.int,.required,.references("MeasureUnit", "MeasureUnitID"))
            .field("PurchaseOrderUnitCost",.double,.required)
            .field("PurchaseOrderState",.bool,.required)
            .field("PurchaseOrderAccountableID",.int)
            .field("PurchasedOrderCreatedAt",.date)
            .field("PurchasedOrderUpdatedAt",.date)
            .unique(on: "PurchaseOrderNumber")
            .create()
    }
}
