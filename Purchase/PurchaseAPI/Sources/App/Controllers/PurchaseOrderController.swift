//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import Vapor
import FluentSQL
import SQLKit

struct PurchaseOrderController: RouteCollection {
    
    
    private let jsonToModel = JSONToModel<PurchaseOrder>()
    
    private enum OperationType { case add, remove }
    
    func boot(routes: RoutesBuilder) throws {
        
        let routeGroup = routes.grouped("PurchaseOrder")
        routeGroup.get(use: index)
        routeGroup.post(use: create)
        routeGroup.patch(use: update)
        routeGroup.delete(use: delete)
    }
    
    
    private func updateArticleAmount(_ value: (operationType:OperationType ,order: PurchaseOrder,req: Request)) -> EventLoopFuture<HTTPStatus>  {
     
        return Article.find(value.order.$articleID.id, on: value.req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({
                let newStock = (value.order.quantity * value.order.unitCost)
                $0.stock = (value.operationType == .add ? $0.stock + newStock : $0.stock - newStock)
                return $0.update(on: value.req.db)
                    .transform(to: .ok)
            })
    }
    
    func index(_ req: Request) throws -> EventLoopFuture<[PurchaseOrder]>
    {
        return PurchaseOrder.query(on: req.db).all()
    }
    
    func create(_ req: Request) throws -> EventLoopFuture<PurchaseOrder> {
        
        let purchaseOrder = try jsonToModel.parse(req)
        
        let result = purchaseOrder.save(on: req.db).map { purchaseOrder }
        
        let _ = updateArticleAmount((operationType: .add,order: purchaseOrder, req: req))
        
        return result
    }
    func update(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        let purchaseOrder = try jsonToModel.parse(req)
        
        let order:EventLoopFuture<HTTPStatus> = PurchaseOrder.find(purchaseOrder.id, on: req.db)
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
        
        let _ = updateArticleAmount((operationType: .add,order: purchaseOrder, req: req))
        
        return order
    }
    
    func delete(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        let purchaseOrder = try jsonToModel.parse(req)
        
        let _ = updateArticleAmount((operationType: .remove,order: purchaseOrder, req: req))
        
        let order:EventLoopFuture<HTTPStatus> = PurchaseOrder.find(purchaseOrder.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({$0.delete(on: req.db).transform(to: .ok)})
        
        let _ = updateArticleAmount((operationType: .remove,order: purchaseOrder, req: req))
        
        return order
    }
}
