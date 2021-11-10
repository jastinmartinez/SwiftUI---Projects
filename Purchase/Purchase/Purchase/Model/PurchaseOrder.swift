//
//  PurchaseOrder.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation


struct PurchaseOrder:Codable {
    
    var id: Int?
    
    var orderNumber: String
    
    var orderDate:Date
    
    var articleID: Int
    
    var quantity: Double
    
    var measureID:Int
    
    var UnitCost: Double
    
}
