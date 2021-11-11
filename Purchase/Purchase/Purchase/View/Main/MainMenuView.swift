//
//  MainMenu.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import SwiftUI

struct MainMenuView: View {
    
    var body: some View {
        
        NavigationView {
            
            ZStack {
                
                RadialGradient(stops:[.init(color: Color(.white), location: 0.3),.init(color: Color(red: 0.1, green: 0.2, blue: 0.45), location: 0.3)], center: .top, startRadius: 100, endRadius: 700)
                    .ignoresSafeArea()
                
                VStack {
                    
                }
            }
            .navigationTitle("Purchase")
        }
    }
}

struct MainMenu_Previews: PreviewProvider {
    static var previews: some View {
        MainMenuView()
    }
}
