//
//  File.swift
//  
//
//  Created by Jastin on 27/11/21.
//

import Foundation
import Vapor

extension User
{
    
    struct Create: Content {
        
        var name: String
        
        var email: String
        
        var password: String
        
        var confirmPassword: String
        
    }
}
