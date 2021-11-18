//
//  DepartmentView.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct DepartmListView: View {
    
    @StateObject private var departmentController =  PurchaseController<Department>()
    
    var body: some View {
        
        List {
            ForEach(departmentController.data, id: \.id ) { department in
                
                NavigationLink(destination: DepartmentCreateAndUpdateOperationView(departmentController: departmentController,department: department).navigationTitle("Nuevo")) {
                    
                    DepartmentView(department: department)
                }
                
            }
            .onDelete(perform: departmentController.remove)
        }
        .refreshable {
            
            departmentController.getAll()
        }
        .navigationTitle("Departamentos")
        .toolbar {
            NavigationLink(destination: DepartmentCreateAndUpdateOperationView(departmentController: departmentController).navigationTitle("Modificar")) {
                Text("Nuevo")
            }
        }
    }
}

struct DepartmentListView_Previews: PreviewProvider {
    static var previews: some View {
        DepartmListView()
    }
}
