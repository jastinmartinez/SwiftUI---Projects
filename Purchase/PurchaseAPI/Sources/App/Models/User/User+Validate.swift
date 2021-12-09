//
//  File.swift
//  
//
//  Created by Jastin on 27/11/21.
//

import Foundation
import Vapor

extension User.Create: Validatable {
    
    static func validations(_ validations: inout Validations) {
        
        validations.add("name", as: String.self, is: !.empty)
        validations.add("email", as: String.self, is: .email)
        validations.add("password",as: String.self, is: .count(8...))
    }
}
