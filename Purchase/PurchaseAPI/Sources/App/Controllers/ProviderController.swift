//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import Vapor


struct ProviderControlelr : RouteCollection {
    
    
    private let jsonToModel = JSONToModel<Provider>()
    
    func boot(routes: RoutesBuilder) throws {
        
        let routeGroup = routes.grouped("Provider")
        routeGroup.get(use: index)
        routeGroup.post(use: create)
        routeGroup.patch(use: update)
        routeGroup.delete(use: delete)
    }
    
    func index(_ req: Request) throws -> EventLoopFuture<[Provider]>
    {
        return Provider.query(on: req.db).all()
    }
    
    func create(_ req: Request) throws -> EventLoopFuture<Provider> {
        
        let provider = try jsonToModel.parse(req)
        
        return provider.save(on: req.db).map { provider }
    }
    func update(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        let provider = try jsonToModel.parse(req)
        
        return Provider.find(provider.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({
                
                $0.comercialName = provider.comercialName
                $0.personID = provider.personID
                $0.state = provider.state
                
                return $0.update(on: req.db)
                    .transform(to: .ok)
            })
    }
    
    func delete(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        let provider = try jsonToModel.parse(req)
        
        return Provider.find(provider.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({$0.delete(on: req.db).transform(to: .ok)})
    }
}
