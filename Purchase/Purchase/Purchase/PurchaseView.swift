//
//  ContentView.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct PurchaseView: View {
    
    var body: some View {
    
        if UserHelper.userInfo != nil {
            
            MainMenuView()
        }
        else {
            
            AuthView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PurchaseView()
    }
}
