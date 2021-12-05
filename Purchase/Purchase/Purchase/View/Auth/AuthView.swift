//
//  AuthView.swift
//  Purchase
//
//  Created by Jastin on 1/12/21.
//

import SwiftUI

struct AuthView: View {
    
    @State  var userSignIn: User.SignIn = User.SignIn(email: "", password: "")
    
    @State  var userSignUp: User.SignUp = User.SignUp(name: "", email: "" ,password: "",confirmPassword: "")
    
    @State private var isSignUp:Bool = false
    
    var body: some View {
    
        VStack {
            
            AuthIconView()
            
            if !isSignUp {
                
                AuthSignInFormView(userSignIn: userSignIn)
            }
            else {
                
                AuthSignUpFormView(userSignUp: userSignUp)
            }
            
            AuthFormButtonAndToggleView(isSignUp: $isSignUp)
        }
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
    }
}
