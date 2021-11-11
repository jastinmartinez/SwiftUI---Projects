//
//  ProviderController.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation


class ProviderController : ObservableObject {
    
    @Published private(set) var providers = [Provider]()
    
    private var providerAPI = APIService<Provider>(apiResource: .Provider)
    
    typealias notifyChangesToView = (Bool) -> ()
    
    init() {
        
        getAll()
    }
    
    func getAll() {
        
        providerAPI.getAll { self.providers = $0 }
    }
    
    func create(_ model: Provider, notify: @escaping notifyChangesToView) {
        
        providerAPI.create(model: model) { result in
            
            if result.id != nil {
                
                self.providers.append(result)
                notify(true)
                
            }
        }
        notify(false)
    }
    
    func update(_ model: Provider, notify: @escaping notifyChangesToView) {
        
        providerAPI.update(model: model) { result in
            
            if result {
                
                if let index  = self.providers.firstIndex(where: { $0.id == model.id }) {
                    
                    self.providers[index] = model
                }
            }
            notify(result)
        }
        notify(false)
    }
    
    func remove(at index: IndexSet) {
        
        for unit in index.map( { providers[$0] } )
        {
            providerAPI.remove(model: unit) { result in
                
                if result {
                    
                    self.providers.remove(atOffsets: index)
                }
            }
        }
    }
}
