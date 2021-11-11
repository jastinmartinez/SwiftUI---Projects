//
//  DepartmentController.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import Foundation
import SwiftUI
import Combine

class DepartmentController : ObservableObject {
    
    @Published var departments = [Department]()
    
    private var departmentAPI = APIService<Department>(apiResource: .Department)
    
    typealias notifyChangesToView = (Bool) -> ()
    
    init () {
        
        getAll()
    }
    
    func getAll() {
        
        departmentAPI.getAll { self.departments = $0 }
    }
    
    func create(_ department: Department, notify: @escaping notifyChangesToView) {
        
        departmentAPI.create(model: department) { dpto in
            
            if dpto.id != nil {
                
             self.departments.append(dpto)
             notify(true)
            
            }
        }
        notify(false)
    }
    
    func update(_ department: Department, notify: @escaping notifyChangesToView) {
        
        departmentAPI.update(model: department) { dpto in
            
            if dpto {
                
                if let index  = self.departments.firstIndex(where: { $0.id == department.id }) {
                    
                    self.departments[index] = department
                }
            }
            notify(dpto)
        }
        notify(false)
    }
    
    func remove(at index: IndexSet) {
        
        for dpto in index.map( { departments[$0] } )
        {
            departmentAPI.remove(model: dpto) { dpto in
                
                if dpto {
                    
                    self.departments.remove(atOffsets: index)
                }
            }
        }
    }
}
