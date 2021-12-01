//
//  Auth.swift
//  Purchase
//
//  Created by Jastin on 1/12/21.
//

import Foundation

struct Auth : Codable {
    
    
    let id: Int?
    
    let name: String
    
    let email: String
    
    let password: String
    
    let passwordConfirmation: String
    
}
