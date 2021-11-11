//
//  MeasureUnitController.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation

class MeasureUnitController : ObservableObject {
    
    @Published private(set) var measureUnits = [MeasureUnit]()
    
    private var measureUnitAPI = APIService<MeasureUnit>(apiResource: .MeasureUnit)
    
    typealias notifyChangesToView = (Bool) -> ()
    
    init() {
        
        getAll()
    }
    
    func getAll() {
        
        measureUnitAPI.getAll { self.measureUnits = $0 }
    }
    
    func create(_ measureUnit: MeasureUnit, notify: @escaping notifyChangesToView) {
        
        measureUnitAPI.create(model: measureUnit) { unit in
            
            if unit.id != nil {
                
             self.measureUnits.append(unit)
             notify(true)
            
            }
        }
        notify(false)
    }
    
    func update(_ measureUnit: MeasureUnit, notify: @escaping notifyChangesToView) {
        
        measureUnitAPI.update(model: measureUnit) { unit in
            
            if unit {
                
                if let index  = self.measureUnits.firstIndex(where: { $0.id == measureUnit.id }) {
                    
                    self.measureUnits[index] = measureUnit
                }
            }
            notify(unit)
        }
        notify(false)
    }
    
    func remove(at index: IndexSet) {
        
        for unit in index.map( { measureUnits[$0] } )
        {
            measureUnitAPI.remove(model: unit) { unit in
                
                if unit {
                    
                    self.measureUnits.remove(atOffsets: index)
                }
            }
        }
    }
}
