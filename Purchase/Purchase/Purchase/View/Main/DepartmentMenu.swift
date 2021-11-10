//
//  DepartmentMenu.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import SwiftUI

struct DepartmentMenu: View {
    var body: some View {
        VStack {
            DepartmentImageView()
            Text("Department")
                .foregroundColor(.white)
                .font(.title)
        }
    }
}

struct DepartmentMenu_Previews: PreviewProvider {
    static var previews: some View {
        DepartmentMenu()
    }
}
