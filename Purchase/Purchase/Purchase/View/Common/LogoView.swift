//
//  DepartmentImage.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import SwiftUI

struct LogoView: View {
   
    var name: String
    
    var body: some View {
        Image(name)
            .resizable()
            .frame(width: 50, height: 50)
    }
}

struct LogoView_Previews: PreviewProvider {
    static var previews: some View {
        LogoView(name: "department")
    }
}
