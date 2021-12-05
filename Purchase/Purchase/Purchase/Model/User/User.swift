//
//  Auth.swift
//  Purchase
//
//  Created by Jastin on 1/12/21.
//

import Foundation

struct User : Decodable {
    
    
    let id: Int?
    
    let name: String
    
    let email: String
    
    let passwordHash: String
    
}
