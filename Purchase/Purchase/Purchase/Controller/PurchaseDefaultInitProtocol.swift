//
//  PurchaseDefaultInitProtocol.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation


protocol PurchaseDefaultInitProtocol {
    
    associatedtype T
    
    func initResource() throws -> APIResources
}

extension PurchaseDefaultInitProtocol {
    
    func initResource() throws -> APIResources {
        
        guard let apiResource = APIResources.init(rawValue: String(describing: T.self)) else { throw ControlleError.InvalidModelToApiResource }
        
        return apiResource
    }

}
