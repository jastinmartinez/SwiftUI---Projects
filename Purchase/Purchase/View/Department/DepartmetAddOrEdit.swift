//
//  DepartmetAddOrEdit.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import SwiftUI

struct DepartmetAddOrEdit: View {
    
    @Environment(\.presentationMode) var presentation
    
    var departmentController: DepartmentController
    
    @State private var name: String = ""
    @State private var state: Bool = true
    @State private var isAnimating: Bool = false
    
    var body: some View {
        
        Form {
            
            VStack(spacing: 30) {
                
                Image("department")
                    .resizable()
                    .frame(width: 100, height: 100)
                
                
                VStack(alignment: .leading, spacing: 15)
                {
                    HStack{
                        if name.isEmpty {
                            Text("*")
                                .foregroundColor(.red)
                        }
                        TextField("Name", text: $name)
                        
                    }
                    Picker("Status", selection: $state) {
                        
                        Text("Active").tag(true)
                        
                        Text("Inactive").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    
                }
                
                if !isAnimating {
                    
                    Button("Save") {
                        
                        if !name.isEmpty {
                            
                            departmentController.create(Department(name: name, state: state)) {
                                
                                if $0 {
                                    isAnimating = false
                                    presentation.wrappedValue.dismiss()
                                }
                                else {
                                    isAnimating = true
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
        DepartmetAddOrEdit(departmentController: DepartmentController())
    }
}
