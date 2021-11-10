//
//  MeasureUnitView.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct MeasureUnitListView: View {
    
    @StateObject var measureUnitController = MeasureUnitController()
    
    var body: some View {
        
        NavigationView {
            
            List {
                
                ForEach(measureUnitController.measureUnits, id:\.id) { measure in
                    
                    NavigationLink {
                        MeasureUnitCreateAndUpdateOperationView(measureUnitController: measureUnitController, measureUnit: measure)
                            .navigationTitle("Edit")
                    }label: {
                        MeasureUnitView(measureUnit: measure)
                    }
                }
                .onDelete(perform: measureUnitController.remove)
            }
            .refreshable { measureUnitController.getAll() }
            .navigationTitle("Measure Unit")
            .toolbar {
                NavigationLink {
                    MeasureUnitCreateAndUpdateOperationView(measureUnitController: measureUnitController)
                        .navigationTitle("Create")
                } label: {
                    Text("New")
                }
            }
        }
    }
}

struct MeasureUnitListView_Previews: PreviewProvider {
    static var previews: some View {
        MeasureUnitListView()
    }
}
