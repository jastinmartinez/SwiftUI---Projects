//
//  AuthFormView.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import SwiftUI

struct AuthSignInFormView: View {
    
    @State var userSignIn: User.SignIn
    
    var body: some View {
        
        VStack {
            
            TextField("Correo",text: $userSignIn.email)
                .keyboardType(.emailAddress)
                .padding()
        
            Divider()
            
            SecureField("Contraseña",text: $userSignIn.password)
                .padding()
               
            Divider()
        }
        .padding()
    }
}

struct AuthSignInFormView_Previews: PreviewProvider {
    static var previews: some View {
        AuthSignInFormView(userSignIn: User.SignIn(email: "", password: ""))
    }
}
