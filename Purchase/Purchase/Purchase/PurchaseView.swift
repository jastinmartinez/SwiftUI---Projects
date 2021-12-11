//
//  ContentView.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct PurchaseView: View {
    
    @State private var userHelp: Bool = UserHelper().userInfo != nil
    
    var body: some View {
    
    
        AuthView().fullScreenCover(isPresented: $userHelp) {

            MainMenuView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PurchaseView()
    }
}
