//
//  PurchaseControllerProtocol.swift
//  Purchase
//
//  Created by Jastin on 18/11/21.
//

import Foundation


protocol PurchaseControllerProtocol {
    
    associatedtype T
    
    typealias notifyChangesToView = (Bool) -> ()
    
    func create(_ model: T, notify: @escaping notifyChangesToView)
    
    func update(_ model: T, notify: @escaping notifyChangesToView)
    
    func remove(at index: IndexSet)
    
    func getAll()
}
