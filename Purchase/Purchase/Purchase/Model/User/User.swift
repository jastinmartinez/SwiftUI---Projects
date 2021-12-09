//
//  Auth.swift
//  Purchase
//
//  Created by Jastin on 1/12/21.
//

import Foundation

struct User : Codable, ModelProtocol {
    
    
    var id: Int?
    
    let name: String
    
    let email: String
    
    let passwordHash: String
    
}
