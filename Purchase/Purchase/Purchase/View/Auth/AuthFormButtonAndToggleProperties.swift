//
//  AuthFormButtonAndToggleProperties.swift
//  Purchase
//
//  Created by Jastin on 9/12/21.
//

import SwiftUI

struct AuthFormButtonAndToggleProperties {
    
    @Binding var isSignUp: Bool
    
    @Binding var isAuthenticationSuccesful: Bool
    
    var signUp: User.SignUp
    
    var signIn: User.SignIn
    
    @State var isAValidationMessageRequired: Bool = false
}
