//
//  Department.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import Foundation

struct Department : ModelProtocol, Codable{

    var id: Int?

    var name: String
    
    var state: Bool
    
    init(id: Int? = nil, name: String, state: Bool) {
        
        self.id = id
        
        self.name = name
        
        self.state = state
    }
}
