//
//  UserDocumentID.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation

class UserDocument {
    
    func verify(_ cedula: String) -> Bool {
        
        var verificator = 0,digit = 0,impairDigit = 0, pairSum = 0,impairSum = 0
        
        if cedula.count == 11 {
        
            for i in stride(from: 9, through: 0, by: -1) {
            
                digit = Array(cedula)[i].wholeNumberValue!
                
                if ((i % 2) != 0) {
                
                    impairDigit = digit * 2
                    
                    if(impairDigit >= 10) {
                    
                        impairDigit -= 9
                    }
                   
                    impairSum += impairDigit
                } else
                {
                    pairSum += digit
                }
            }
            
            verificator = 10 - ((pairSum + impairSum) % 10)
           
            if(((verificator == 10) && (cedula.last!.wholeNumberValue! == 0)) || (verificator == cedula.last!.wholeNumberValue!)) {
            
                return true
            }
        }
        
        return false
    }
}
