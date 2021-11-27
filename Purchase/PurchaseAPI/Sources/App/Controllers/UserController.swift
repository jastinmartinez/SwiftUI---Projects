//
//  File.swift
//  
//
//  Created by Jastin on 27/11/21.
//

import Foundation
import Vapor



struct UserController: RouteCollection {
    
    private let jsonToModel = JSONToModel<User.Create>()
    
    func boot(routes: RoutesBuilder) throws {
        
        let userRoute = routes.grouped("Auth")
        
        userRoute.post("SignUp",use: signup)
        
        userRoute.grouped(User.authenticator()).post("SignIn",use: signin)
    }
    
    func signup(req: Request) throws -> EventLoopFuture<User> {
        
        try User.Create.validate(content: req)
        
        let jsonToUser = try  jsonToModel.parse(req)
        
        guard jsonToUser.password == jsonToUser.confirmPassword else {
            
            throw Abort(.badRequest, reason: "Password did not match")
        }
        
        let user =  try User( name: jsonToUser.name, email: jsonToUser.email, passwordHash: Bcrypt.hash(jsonToUser.password) )
        
        return user.save(on: req.db).map({ user })
    }
    
    
    func signin(req: Request) throws -> User {
        
        return try req.auth.require(User.self)
    }
}
