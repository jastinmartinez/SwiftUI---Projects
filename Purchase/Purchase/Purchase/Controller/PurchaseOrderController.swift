//
//  PurchaseOrderController.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import Foundation

class PurchaseOrderController: ObservableObject {
    
    @Published private(set) var purchaseOrders = [PurchaseOrder]()
    
    private var purchaserOrderAPI = APIService<PurchaseOrder>(apiResource: .PurchaseOrder)
    
    typealias notifyChangesToView = (Bool) -> ()
    
    init() {
        
        getAll()
    }
    
    func getAll() {
        
        purchaserOrderAPI.getAll { self.purchaseOrders = $0 }
    }
    
    func create(_ model: PurchaseOrder, notify: @escaping notifyChangesToView) {
        
        purchaserOrderAPI.create(model: model) { result in
            
            if result.id != nil {
                
                self.purchaseOrders.append(result)
                notify(true)
                
            }
        }
        notify(false)
    }
    
    func update(_ model: PurchaseOrder, notify: @escaping notifyChangesToView) {
        
        purchaserOrderAPI.update(model: model) { result in
            
            if result {
                
                if let index  = self.purchaseOrders.firstIndex(where: { $0.id == model.id }) {
                    
                    self.purchaseOrders[index] = model
                }
            }
            notify(result)
        }
        notify(false)
    }
    
    func remove(at index: IndexSet) {
        
        for unit in index.map( { purchaseOrders[$0] } )
        {
            purchaserOrderAPI.remove(model: unit) { result in
                
                if result {
                    
                    self.purchaseOrders.remove(atOffsets: index)
                }
            }
        }
    }
}
