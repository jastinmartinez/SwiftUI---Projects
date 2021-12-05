//
//  AuthSignUpFormView.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import SwiftUI

struct AuthSignUpFormView: View {
    
    @State var userSignUp: User.SignUp
    
    var body: some View {
        
        VStack {
        
            TextField("Correo",text: $userSignUp.email)
                .keyboardType(.emailAddress)
                .padding()
               
            Divider()
    
            TextField("Nombre",text: $userSignUp.name)
                .keyboardType(.namePhonePad)
                .padding()
               
            Divider()
            SecureField("Contraseña",text: $userSignUp.password)
                .padding()
               
            
            Divider()
            SecureField("Confirmar Contraseña",text: $userSignUp.confirmPassword)
                .padding()
            Divider()
               
        }
        .padding()
    }
}

struct AuthSignUpFormView_Previews: PreviewProvider {
    static var previews: some View {
        AuthSignUpFormView(userSignUp: User.SignUp(name: "", email: "" ,password: "",confirmPassword: ""))
    }
}
