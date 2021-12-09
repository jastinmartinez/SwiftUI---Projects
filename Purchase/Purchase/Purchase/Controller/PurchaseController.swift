//
//  PurchaseController.swift
//  Purchase
//
//  Created by Jastin on 18/11/21.
//

import Foundation


class PurchaseController<T: ModelProtocol > : ObservableObject , PurchaseControllerProtocol,PurchaseDefaultInitProtocol {
    
    @Published private (set) var data = [T]()
    
    private var apiService:APIService<T>?
    
    typealias T = T
    
    init() {
        
        do {
            
             let apiResource = try initResource()
            
             apiService =  APIService<T>(apiResource: apiResource)
            
             getAll()
        }
        
        catch {
            
            print(error)
        }
    }
    
    func create(_ model: T, notify: @escaping notifyChangesToView) {
        
        apiService?.create(model: model) { result in
            
            if result.id != nil {
                
                self.data.append(result)
                
                notify(true)
            }
        }
        notify(false)
    }
    
    func update(_ model: T, notify: @escaping notifyChangesToView) {
        
        apiService?.update(model: model) { result in
            
            if result {
                
                if let index  = self.data.firstIndex(where: { $0.id == model.id }) {
                    
                    self.data[index] = model
                }
            }
            
            notify(result)
        }
        
        notify(false)
    }
    
    func remove(at index: IndexSet) {
        
        for model in index.map( { data[$0] } )
        {
            apiService?.remove(model: model) { result in
                
                if result {
                    
                    self.data.remove(atOffsets: index)
                }
            }
        }
    }
    
    func getAll() {
        
        apiService?.getAll { datas in
            
            self.data = datas
        }
    }
}
