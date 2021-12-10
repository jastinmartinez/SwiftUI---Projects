//
//  PasswordTextFieldView.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import SwiftUI

struct PasswordTextFieldView: View {
    
    @State private var validationDescription: String = ""
    
    var passwordTitle: String = "Contraseña"

    @Binding var password: String
    
    var body: some View {
        
        SecureField(passwordTitle,text: $password)
            .padding()
            .onChange(of: password){
                
                password = $0.trimmingCharacters(in: .whitespaces)
                
                validationDescription = AuthValidation().passwordValidation($0)
                
            }
        
        if !validationDescription.isEmpty {
            
            Text(validationDescription)
                .foregroundColor(.red)
        }
    }
}

struct PasswordTextFieldView_Previews: PreviewProvider {
    static var previews: some View {
        PasswordTextFieldView( passwordTitle: "", password: .constant("") )
    }
}
