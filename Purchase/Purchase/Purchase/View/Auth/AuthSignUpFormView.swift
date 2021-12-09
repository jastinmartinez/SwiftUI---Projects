//
//  AuthSignUpFormView.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import SwiftUI

struct AuthSignUpFormView: View {
    
    @Binding var userSignUp: User.SignUp
    
    var body: some View {
        
        VStack {
            
            EmailAddressTextFieldView(emailAddress: $userSignUp.email)
            Divider()
            
            TextField("Nombre",text: $userSignUp.name)
                .keyboardType(.namePhonePad)
                .padding()
            Divider()
            
            PasswordTextFieldView(password: $userSignUp.password)
            Divider()
            
            PasswordTextFieldView(password: $userSignUp.confirmPassword)
            Divider()
            
        }
        .padding()
    }
}

struct AuthSignUpFormView_Previews: PreviewProvider {
    static var previews: some View {
        AuthSignUpFormView(userSignUp: .constant( User.SignUp(name: "", email: "" ,password: "",confirmPassword: "")))
    }
}
