//
//  AuthFormButtonAndToggle.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import SwiftUI

struct AuthFormButtonAndToggleView: View {
    
    var authFormButtonAndToggleProperties: AuthFormButtonAndToggleProperties
    
    private (set) var authController:AuthController =  AuthController()
    
    var body: some View {
        
        VStack {
            
            Toggle(authFormButtonAndToggleProperties.isSignUp ? "Iniciar Sesion?" : "Regitrarse?",isOn: authFormButtonAndToggleProperties.$isSignUp)
                .foregroundColor(.secondary)
                .padding()
            
            HStack {
                
                Spacer()
                
                Button(!authFormButtonAndToggleProperties.isSignUp ? "Iniciar Sesion" : "Regitrarse" ) {
                    
                    if authFormButtonAndToggleProperties.isSignUp {
                        
                        authController.authenticateSignUp(authFormButtonAndToggleProperties.signUp) { authFormButtonAndToggleProperties.isAuthenticationSuccesful = $0 }
                        
                    }
                    else {
                        
                        authController.authenticateSignIn(authFormButtonAndToggleProperties.signIn) { authFormButtonAndToggleProperties.isAuthenticationSuccesful = $0 }
                    }
                }
                Spacer()
            }
            .padding()
        }
    }
}

struct AuthFormButtonAndToggle_Previews: PreviewProvider {
    static var previews: some View {
        
        AuthFormButtonAndToggleView(authFormButtonAndToggleProperties: AuthFormButtonAndToggleProperties(isSignUp: .constant(false), isAuthenticationSuccesful: .constant(false), signUp:User.SignUp(name: "", email: "" ,password: "",confirmPassword: "") ,signIn: User.SignIn(email: "", password: "")))
    }
}

