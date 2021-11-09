//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import Vapor

struct ArticleController: RouteCollection {
    
    private let jsonToModel = JSONToModel<Article>()
    
    func boot(routes: RoutesBuilder) throws {
        
        let routeGroup = routes.grouped("Article")
        routeGroup.get(use: index)
        routeGroup.post(use: create)
        routeGroup.patch(use: update)
        routeGroup.delete(":id",use: delete)
    }
    
    func index(_ req: Request) throws -> EventLoopFuture<[Article]>
    {
        return Article.query(on: req.db).all()
    }
    
    func create(_ req: Request) throws -> EventLoopFuture<Article> {
        
        let article = try jsonToModel.parse(req)
        
        return article.save(on: req.db).map { article }
    }
    func update(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        let article = try jsonToModel.parse(req)
        
        return Article.find(article.id, on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({
                
                $0.description = article.description
                $0.mark = article.mark
                $0.$measureUnitID.id = article.$measureUnitID.id
                $0.stock = article.stock
                $0.state = article.state
                
                return $0.update(on: req.db)
                    .transform(to: .ok)
            })
    }
    
    func delete(_ req: Request) throws -> EventLoopFuture<HTTPStatus>
    {
        return Article.find(req.parameters.get("id"), on: req.db)
            .unwrap(or: Abort(.notFound))
            .flatMap({$0.delete(on: req.db).transform(to: .ok)})
    }
}

