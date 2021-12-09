//
//  AuthFormButtonAndToggle.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import SwiftUI

struct AuthFormButtonAndToggleView: View {
    
    @Binding var isSignUp: Bool
    
    @Binding var isAuthenticationSuccesful: Bool
    
    var authController =  AuthController()
    
    var signUp: User.SignUp
    
    var signIn: User.SignIn
    
    var body: some View {
        
        let buttonTitle = !isSignUp ? "Iniciar Sesion" : "Regitrarse"
        
        let toggleTitile = isSignUp ? "Iniciar Sesion?" : "Regitrarse?"
        
        VStack {
            
            Toggle(toggleTitile,isOn: $isSignUp)
                .foregroundColor(.secondary)
                .padding()
            
            HStack {
                
                Spacer()
                
                Button(buttonTitle) {
                    
                    if isSignUp {
                        
                        if   AuthValidation().emailValidation(email: signUp.email) && AuthValidation().passwordValidation(signUp.password).isEmpty  && signUp.isPasswordSame {
                            
                            authController.authenticateSignUp(signUp) { isAuthenticationSuccesful = $0 }
                        }
                    }
                    else {
                        if   AuthValidation().emailValidation(email: signUp.email) && !AuthValidation().passwordValidation(signUp.password).isEmpty  {
                         
                            authController.authenticateSignIn(signIn) { isAuthenticationSuccesful = $0 }
                        }
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
        
        AuthFormButtonAndToggleView(isSignUp: .constant(false), isAuthenticationSuccesful: .constant(false), signUp:User.SignUp(name: "", email: "" ,password: "",confirmPassword: "") ,signIn: User.SignIn(email: "", password: ""))
    }
}
