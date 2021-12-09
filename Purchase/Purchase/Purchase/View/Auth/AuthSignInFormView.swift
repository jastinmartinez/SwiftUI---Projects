//
//  AuthFormView.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import SwiftUI

struct AuthSignInFormView: View {
    
    @Binding var userSignIn: User.SignIn
    
    var body: some View {
        
        VStack {
            
            EmailAddressTextFieldView(emailAddress: $userSignIn.email)
        
            Divider()
            
            PasswordTextFieldView(password: $userSignIn.password)
            
            Divider()
        }
        .padding()
    }
}

struct AuthSignInFormView_Previews: PreviewProvider {
    static var previews: some View {
        AuthSignInFormView(userSignIn: .constant( User.SignIn(email: "", password: "")))
    }
}
