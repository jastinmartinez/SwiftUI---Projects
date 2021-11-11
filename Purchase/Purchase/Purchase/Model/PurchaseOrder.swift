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
    
    var orderDate:String
    
    var articleID: Parent
    
    var quantity: Double
    
    var measureUnitID: Parent
    
    var unitCost: Double
    
}
