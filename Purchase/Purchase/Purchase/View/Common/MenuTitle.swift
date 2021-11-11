//
//  MenuTitle.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct MenuTitle: View {
    var name:String
    var body: some View {
        Text(name)
            .foregroundColor(.white)
            .fontWeight(.bold)
    }
}

struct MenuTitle_Previews: PreviewProvider {
    static var previews: some View {
        MenuTitle(name: "Ejemeplo")
    }
}
