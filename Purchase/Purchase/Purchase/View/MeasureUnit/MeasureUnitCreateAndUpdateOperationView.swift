//
//  MeasureUnitCreateView.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct MeasureUnitCreateAndUpdateOperationView: View {
    
    
    @Environment(\.presentationMode) private var presentation
    
    @StateObject var measureUnitController: PurchaseController<MeasureUnit>
    
    @State var measureUnit: MeasureUnit = MeasureUnit(id: nil, description: "", state: true)
    
    @State var isClicked = false
    
    fileprivate func isOperationComplete(_ completion: Bool) {
        
        if completion {
            
            isClicked = !completion
            presentation.wrappedValue.dismiss()
            
        }
    }
    
    var body: some View {
        
        
        Form {
            
            Section("Unidad De Medida") {
                
                VStack() {
                    
                    if measureUnit.id != nil {
                        
                        Text("\(measureUnit.id!)")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .fontWeight(.bold)
                    }
                    
                    HStack{
                        
                        if measureUnit.description.isEmpty {
                            Text("*")
                                .foregroundColor(.red)
                        }
                        
                        TextField("Descripcion",text: $measureUnit.description)
                        
                    }
                    
                    
                    StatusPicker(status: $measureUnit.state)
                }
                
                HStack {
                    
                    Spacer()
                    
                    if !isClicked {
                        
                        
                        Button("Guardar", action: {
                            
                            guard !measureUnit.description.isEmpty else { return }
                            
                            isClicked = true
                            
                            if measureUnit.id != nil {
                                
                                self.measureUnitController.update(measureUnit) { isOperationComplete($0) }
                            }
                            else {
                                self.measureUnitController.create(measureUnit) { isOperationComplete($0) }
                            }
                        })
                        
                    }
                    else {
                        ActivityIndicator(isAnimating: $isClicked, style: .medium)
                    }
                }
            }
            
            
        }
    }
}


struct MeasureUnitCreateAndUpdateOperationView_Previews: PreviewProvider {
    static var previews: some View {
        MeasureUnitCreateAndUpdateOperationView(measureUnitController: PurchaseController<MeasureUnit>(), measureUnit: MeasureUnit(id: nil, description: "", state: true))
    }
}
