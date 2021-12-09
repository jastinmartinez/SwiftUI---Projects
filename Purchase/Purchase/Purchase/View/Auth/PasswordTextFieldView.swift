//
//  PasswordTextFieldView.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import SwiftUI

struct PasswordTextFieldView: View {
    
    @State private var validationDescription: String = ""
    
    @Binding var password: String
    
    var body: some View {
        
        SecureField("Contraseña",text: $password)
            .padding()
            .onChange(of: password){ validationDescription = AuthValidation().passwordValidation($0) }
        
        if !validationDescription.isEmpty {
            
            Text(validationDescription)
                .foregroundColor(.red)
        }
    }
}

struct PasswordTextFieldView_Previews: PreviewProvider {
    static var previews: some View {
        PasswordTextFieldView( password: .constant(""))
    }
}
