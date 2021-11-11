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
    var orderDate: String
    
    @Parent(key: "PurchaseOrderArticleID")
    var articleID: Article
    
    @Field(key: "PurchaseOrderQuantity")
    var quantity: Double
    
    @Parent(key: "PurchaseOrderMeasureUnitID")
    var measureUnitID: MeasureUnit
    
    @Field(key: "PurchaseOrderUnitCost")
    var unitCost: Double
    
    @Timestamp(key: "PurchasedOrderCreatedAt", on: .create, format: .default)
    var createdAt: Date?
    
    @Timestamp(key: "PurchasedOrderUpdatedAt", on: .update, format: .default)
    var updatedAt: Date?
    
    init() { }
    
    init(id: Int? = nil, orderNumber: String, orderDate: String, article: Int,measureUnitID: Int ,quantity: Double,unitCost: Double) {
        self.id = id
        self.orderNumber = orderNumber
        self.orderDate = orderDate
        self.$articleID.id = article
        self.$measureUnitID.id = measureUnitID
        self.quantity = quantity
        self.unitCost = unitCost
    }
}
