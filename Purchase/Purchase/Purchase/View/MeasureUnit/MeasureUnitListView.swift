//
//  MeasureUnitView.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct MeasureUnitListView: View {
    
    @StateObject var measureUnitController = PurchaseController<MeasureUnit>()
    
    var body: some View {
        
        List {
            
            ForEach(measureUnitController.data, id:\.id) { measure in
                
                NavigationLink {
                    MeasureUnitCreateAndUpdateOperationView(measureUnitController: measureUnitController, measureUnit: measure)
                        .navigationTitle("Modificar")
                }label: {
                    MeasureUnitView(measureUnit: measure)
                }
            }
            .onDelete(perform: measureUnitController.remove)
        }
        .refreshable { measureUnitController.getAll() }
        .navigationTitle("Unidad de Medida")
        .toolbar {
            NavigationLink {
                MeasureUnitCreateAndUpdateOperationView(measureUnitController: measureUnitController)
                    .navigationTitle("Nuevo")
            } label: {
                Text("Nuevo")
            }
        }
    }
}

struct MeasureUnitListView_Previews: PreviewProvider {
    static var previews: some View {
        MeasureUnitListView()
    }
}
