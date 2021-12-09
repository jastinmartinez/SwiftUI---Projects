//
//  AuthValidation.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation

final class AuthValidation {
    
    func emailValidation(email: String) -> Bool  {
        
        let emailAddressRegexPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        
        let emailAddressPredicate = NSPredicate(format:"SELF MATCHES %@", emailAddressRegexPattern)
        
        return emailAddressPredicate.evaluate(with: email)
    }
    
     func passwordValidation(_ password: String) -> String {
        
        if password.isEmpty {
            
            return  "Digitar Contraseña"
        }
        else if password.count < 8 {
            
            return "Minimo requerido (8), resta \(8 - password.count)"
        }
        else {
            
            return  ""
        }
    }
}
