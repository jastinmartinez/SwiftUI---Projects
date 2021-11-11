//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import Vapor
struct DepartmentController : RouteCollection {
    
    
    private let jsonToModel = JSONToModel<Department>()
    
    func boot(routes: RoutesBuilder) throws {
        
        let routeGroup = routes.grouped("Department")
        routeGroup.post( use: create)
        routeGroup.get( use: index)
        routeGroup.patch( use: update)
        routeGroup.delete(use: delete)
    }
    
    func index(req: Request) throws -> EventLoopFuture<[Department]>
    {
        return Department.query(on: req.db).all()
    }
    
    func create(req: Request) throws -> EventLoopFuture<Department> {
        
        let department = try jsonToModel.parse(req)
        
        return department.save(on: req.db).map { department }
    }
    
    func update(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let department = try jsonToModel.parse(req)
        
        return Department.find(department.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap {
                $0.name = department.name
                $0.state = department.state
                return $0.update(on: req.db)
                    .transform(to: .ok)
        }
    }
    
    func delete(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        
        let department = try jsonToModel.parse(req)
        
        return Department.find(department.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap { $0.delete(on: req.db) }
            .transform(to: .ok)
    }
}
