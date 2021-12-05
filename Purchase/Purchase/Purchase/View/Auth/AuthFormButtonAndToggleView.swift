//
//  AuthFormButtonAndToggle.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import SwiftUI

struct AuthFormButtonAndToggleView: View {
    
    @Binding var isSignUp: Bool
   
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
                    
                }
                Spacer()
            }
            .padding()
        }
    }
}

struct AuthFormButtonAndToggle_Previews: PreviewProvider {
    static var previews: some View {
        AuthFormButtonAndToggleView(isSignUp: .constant(false))
    }
}
