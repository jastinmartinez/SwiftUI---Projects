//
//  DepartmentDetailView.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct DepartmentDetailView: View {
    
    var department: Department
    
    var body: some View {
        VStack() {
            HStack {
                Image("department")
                    .resizable()
                    .frame(width: 50, height: 50)
                
                VStack(alignment: .leading,spacing: 2) {
                    Text("\(department.id ?? 0)")
                    Text(department.name)
                    Text(department.state.toString())
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct DepartmentDetailView_Previews: PreviewProvider {
    static var previews: some View {
        DepartmentDetailView(department: Department(id: 1, name: "Example", state: true))
    }
}
