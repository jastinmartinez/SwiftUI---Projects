//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation

final class Department: DbModel {
    
    static let schema = "Department"
    
    @ID(custom: "DepartmentID", generatedBy: .database)
    var id: Int?
    
    @Field(key: "DepartmentName")
    var name: String
    
    @Field(key: "DepartmentState")
    var state: Bool
    
    init () {}
    
    init(id: Int? = nil, name: String , state: Bool)
    {
        self.id = id
        self.name = name
        self.state = state
    }
}
