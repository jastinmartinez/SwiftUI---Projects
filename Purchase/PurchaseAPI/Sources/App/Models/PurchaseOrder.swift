//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import FluentKit

final class PurchaseOrder: DbModel {
    
    static var schema: String = "PurchaseOrder"
    
    @ID(custom: "PurchaseOrderID", generatedBy: .database)
    var id: Int?
    
    @Field(key: "PurchaseOrderNumber")
    var orderNumber: String
    
    @Field(key: "PurchaseOrderDate")
    var orderDate: Date
    
    @Parent(key: "ArticleID")
    var articleID: Article
    
    @Field(key: "PurchaseOrderQuantity")
    var quantity: Double
    
    @Parent(key: "MeasureUnitID")
    var measureUnitID: MeasureUnit
    
    @Field(key: "PurchaseOrderUnitCost")
    var unitCost: Double
    
    @Timestamp(key: "PurchasedOrderCreatedAt", on: .create, format: .default)
    var createdAt: Date?
    
    @Timestamp(key: "PurchasedOrderUpdatedAt", on: .update, format: .default)
    var updatedAt: Date?
    
    init() { }
    
    init(id: Int? = nil, orderNumber: String, orderDate: Date, article: Int,quantity: Double,unitCost: Double,createdAt: Date? = nil,updatedAt: Date? = nil) {
        self.id = id
        self.orderNumber = orderNumber
        self.orderDate = orderDate
        self.$articleID.id = article
        self.quantity = quantity
        self.unitCost = unitCost
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
