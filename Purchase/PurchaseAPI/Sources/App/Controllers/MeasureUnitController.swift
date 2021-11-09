//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import Vapor

struct MeasureUnitController: RouteCollection {
    
    
    let jsonParse = JSONToModel<MeasureUnit>()
    
    func boot(routes: RoutesBuilder) throws {
        
        let routeGroup = routes.grouped("MeasureUnit")
        routeGroup.get(use: index)
        routeGroup.post(use: create)
        routeGroup.patch(use: update)
        routeGroup.delete(":id",use: delete)
    }
    
    func create(_ req: Request) throws -> EventLoopFuture<MeasureUnit> {
        
        let measureUnit = try jsonParse.parse(req)
        
        return measureUnit.save(on: req.db).map { measureUnit }
    }
    
    func index(_ req: Request) throws -> EventLoopFuture<[MeasureUnit]>
    {
        return MeasureUnit.query(on: req.db).all()
    }
    
    func update(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        let measureUnit = try jsonParse.parse(req)
        
        return MeasureUnit.find(measureUnit.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({
                
                $0.description = measureUnit.description
                $0.state = measureUnit.state
                
                return $0.update(on: req.db)
                    .transform(to: .ok)
            })
    }
    
    func delete(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        return MeasureUnit.find(req.parameters.get("id"), on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({$0.delete(on: req.db).transform(to: .ok)})
    }
}
