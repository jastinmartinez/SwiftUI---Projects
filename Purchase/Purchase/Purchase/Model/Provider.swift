//
//  Provider.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation

struct Provider: ModelProtocol,Codable {
    
    var id: Int?
    
    var personID: String
    
    var comercialName: String
    
    var state: Bool
}
