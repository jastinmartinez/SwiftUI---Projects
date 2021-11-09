//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation

final class MeasureUnit: DbModel {
    
    static var schema: String = "MeasureUnit"
    
    @ID(custom: "MeasureUnitID", generatedBy: .database)
    var id: Int?
    
    @Field(key: "MeasureUnitDescription")
    var description: String
    
    @Field(key: "MeasureUnitState")
    var state: Bool
    
    init () {}
    
    init (id: Int? = nil, description: String, state: Bool )
    {
        self.id = id
        self.description = description
        self.state = state
    }
}
