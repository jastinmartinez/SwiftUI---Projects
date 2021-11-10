//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import Vapor

struct PurchaseOrderController: RouteCollection {
    
    private let jsonToModel = JSONToModel<PurchaseOrder>()
    
    func boot(routes: RoutesBuilder) throws {
        
        let routeGroup = routes.grouped("PurchaseOrder")
        routeGroup.get(use: index)
        routeGroup.post(use: create)
        routeGroup.patch(use: update)
        routeGroup.delete(use: delete)
    }
    
    func index(_ req: Request) throws -> EventLoopFuture<[PurchaseOrder]>
    {
        return PurchaseOrder.query(on: req.db).all()
    }
    
    func create(_ req: Request) throws -> EventLoopFuture<PurchaseOrder> {
        
        let purchaseOrder = try jsonToModel.parse(req)
        
        return purchaseOrder.save(on: req.db).map { purchaseOrder }
    }
    func update(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        let purchaseOrder = try jsonToModel.parse(req)
        
        return PurchaseOrder.find(purchaseOrder.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({
                
                $0.orderNumber = purchaseOrder.orderNumber
                $0.orderDate = purchaseOrder.orderDate
                $0.$articleID.id = purchaseOrder.$articleID.id
                $0.quantity = purchaseOrder.quantity
                $0.$measureUnitID.id = purchaseOrder.$measureUnitID.id
                $0.unitCost = purchaseOrder.unitCost
                
                return $0.update(on: req.db)
                    .transform(to: .ok)
            })
    }
    
    func delete(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        let purchaseOrder = try jsonToModel.parse(req)
        
        return PurchaseOrder.find(purchaseOrder.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({$0.delete(on: req.db).transform(to: .ok)})
    }
}
