//
//  DepartmentDetailView.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct DepartmentView: View {
    
    var department: Department
    
    var body: some View {
        
        VStack {
            
            HStack {
                Spacer()
                LogoView(name: "department")
            }
            
            HStack(spacing: 20) {
                
                
                Text("\(department.id!)")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
                
                HStack {
                    Spacer()
                    VStack(alignment: .trailing) {
                        
                        Text(department.name)
                        Text(department.state.toString())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct DepartmentView_Previews: PreviewProvider {
    static var previews: some View {
        DepartmentView(department: Department(id: 1, name: "Example", state: true))
    }
}
