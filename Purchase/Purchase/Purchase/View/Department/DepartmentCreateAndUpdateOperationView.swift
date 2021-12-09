//
//  DepartmetAddOrEdit.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct DepartmentCreateAndUpdateOperationView: View {
    
    @Environment(\.presentationMode) var presentation
    
    @StateObject var departmentController: PurchaseController<Department>
    
    @State var department: Department = Department(id: nil, name: "", state: true)
    
    @State private var isAnimating: Bool = false
    
    fileprivate func IsProcessComplete(_ value: Bool) {
       
        if value {
            isAnimating = false
            presentation.wrappedValue.dismiss()
        }
        else {
            isAnimating = true
        }
    }
    
    var body: some View {
        
        Form {
            
            VStack(spacing: 15) {
                
                VStack(alignment: .leading, spacing: 15)
                {
                    
                    if let id = department.id {
                        
                        Text("\(id)")
                        
                    }
                    HStack{
                        if department.name.isEmpty {
                            Text("*")
                                .foregroundColor(.red)
                        }
                        TextField("Nombre", text: $department.name)
                        
                    }
                    
                    StatusPicker(status: $department.state)
                }
                
                HStack {
                    Spacer()
                    if !isAnimating {
                        
                        Button("Guardar") {
                            
                            if !department.name.isEmpty {
                                
                                if department.id != nil {
                                    departmentController.update(department) {
                                        
                                        IsProcessComplete($0)
                                    }
                                }
                                else {
                                    departmentController.create(department) {
                                        
                                        IsProcessComplete($0)
                                    }
                                }
                            }
                        }
                    }
                    else {
                        ActivityIndicator(isAnimating: $isAnimating, style: .large)
                    }
                }
            }
        }
    }
}

struct DepartmetCreateAndUpdateOperation_Previews: PreviewProvider {
    static var previews: some View {
        DepartmentCreateAndUpdateOperationView(departmentController:  PurchaseController<Department>() )
    }
}
