//
//  AuthenticationFormView.swift
//  AdoptMe
//
//  Created by Jastin on 11/5/21.
//

import SwiftUI

struct AuthenticationFormView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    
    var body: some View {
        ZStack{
            VStack {
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button(action: {}, label: {
                    Text("SIGN IN")
                        .font(.title)
                        .foregroundColor(.white)
                })
                .frame(width: 220)
                .background(Color("ColorWatermelonDark"))
                .cornerRadius(10)
            }.padding(.horizontal,50)
            
        }
    }
}

struct AuthenticationFormView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationFormView()
            
    }
}
