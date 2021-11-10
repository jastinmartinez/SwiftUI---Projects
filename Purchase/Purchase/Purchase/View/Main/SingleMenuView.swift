//
//  DepartmentMenu.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import SwiftUI

struct SingleMenuView: View {
    
    var menu: Menu
    
    var body: some View {
        
        VStack {
            Image(menu.Image)
                .resizable()
                .frame(width: 50, height: 50)
            Text(menu.name)
                .foregroundColor(.white)
                
        }
    }
}

struct DepartmentMenu_Previews: PreviewProvider {
    static var previews: some View {
        SingleMenuView(menu: Menu(name: "Department", Image: "department"))
    }
}
