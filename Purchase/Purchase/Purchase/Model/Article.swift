//
//  Article.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation

struct Article: Codable {
    
    var id: Int?
    
    var description: String
    
    var mark: String
    
    var measureUnitID: Int
    
    var stock: Double
    
    var state: Bool
}
