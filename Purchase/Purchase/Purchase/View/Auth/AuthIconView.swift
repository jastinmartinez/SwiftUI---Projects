//
//  AuthIconView.swift
//  Purchase
//
//  Created by Jastin on 5/12/21.
//

import SwiftUI

struct AuthIconView: View {
    
    var body: some View {
       
        VStack {
            
            Text("Purchase Manage System")
                .font(.largeTitle)
                .foregroundColor(.blue)
                .bold()
            
            Image("shop")
                .resizable()
                .frame(width: 150, height: 150)
                .clipped()
                .cornerRadius(30)
        }
    }
}

struct AuthIconView_Previews: PreviewProvider {
    static var previews: some View {
        AuthIconView()
    }
}
