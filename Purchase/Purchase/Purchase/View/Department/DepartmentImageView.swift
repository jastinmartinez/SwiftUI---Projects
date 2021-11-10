//
//  DepartmentImage.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import SwiftUI

struct DepartmentImageView: View {
    var body: some View {
        Image("department")
            .resizable()
            .frame(width: 50, height: 50)
    }
}

struct DepartmentImage_Previews: PreviewProvider {
    static var previews: some View {
        DepartmentImageView()
    }
}
