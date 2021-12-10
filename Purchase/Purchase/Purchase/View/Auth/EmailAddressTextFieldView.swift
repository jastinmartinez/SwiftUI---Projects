//
//  MailTextFieldView.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import SwiftUI

struct EmailAddressTextFieldView: View {
    
    @Binding var emailAddress: String
    
    @State private var isAValidationRequired:Bool = false
    
    var body: some View {
        
        VStack {
            
            TextField("Correo",text: $emailAddress)
                .keyboardType(.emailAddress)
                .padding()
                .onChange(of: emailAddress) {
                    
                    emailAddress = $0.trimmingCharacters(in: .whitespaces).lowercased()
                    
                    isAValidationRequired = !AuthValidation().emailValidation(email: $0)
                }
            
            if isAValidationRequired {
                
                Text("Direccion de correo invalida")
                    .foregroundColor(.red)
                
            }
        }
    }
}

struct MailTextFieldView_Previews: PreviewProvider {
    static var previews: some View {
        EmailAddressTextFieldView(emailAddress: .constant(""))
    }
}
