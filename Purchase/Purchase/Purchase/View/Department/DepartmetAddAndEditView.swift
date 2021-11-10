//
//  DepartmetAddOrEdit.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct DepartmetAddAndEditView: View {
    
    @Environment(\.presentationMode) var presentation
    
    @StateObject var departmentController: DepartmentController
    
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
            
            VStack(spacing: 30) {
                
                DepartmentImageView()
                
                
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
                        TextField("Name", text: $department.name)
                        
                    }
                    Picker("Status", selection: $department.state) {
                        
                        Text("Active").tag(true)
                        
                        Text("Inactive").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    
                }
                
                if !isAnimating {
                    
                    Button("Save") {
                        
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
                
                ActivityIndicator(isAnimating: $isAnimating, style: .large)
            }
        }
    }
}

struct DepartmetAddOrEdit_Previews: PreviewProvider {
    static var previews: some View {
        DepartmetAddAndEditView(departmentController: DepartmentController())
    }
}
