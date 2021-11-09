//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation

final class Provider: DbModel {
    
    static var schema: String = "Provider"
    
    @ID(custom: "ProviderID", generatedBy: .database)
    var id: Int?
    
    @Field(key: "ProviderPersonID")
    var personID: String
    
    @Field(key:"ProviderComercialName")
    var comercialName: String
    
    @Field(key:"ProviderState")
    var state: Bool
    
    init() {}
    
    init(id: Int? = nil, personID: String, comercialName:String, state:Bool) {
        
        self.id = id
        self.personID = personID
        self.comercialName = comercialName
        self.state = state
    }
}
