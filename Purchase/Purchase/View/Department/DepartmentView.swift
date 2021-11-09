//
//  DepartmentView.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct DepartmentView: View {
    
    @StateObject private var departmentController = DepartmentController()
    
    var body: some View {
        
        NavigationView {
            VStack {
                
                List {
                    ForEach(departmentController.departments, id: \.self ) { department in
                        
                        DepartmentDetailView(department: department)
                    }
                    .onDelete(perform: departmentController.remove)
                }
            }.refreshable {
                
                departmentController.getAll()
            }
            .navigationTitle("Department")
            .toolbar {
                NavigationLink(destination: DepartmetAddOrEdit(departmentController: departmentController)) {
                    Text("New")
                }
            }
        }
    }
}

struct DepartmentView_Previews: PreviewProvider {
    static var previews: some View {
        DepartmentView()
    }
}
