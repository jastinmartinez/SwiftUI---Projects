//
//  File.swift
//  
//
//  Created by Jastin on 7/11/21.
//

import Foundation
import FluentKit

final class Article : DbModel {
    
    static var schema: String = "Article"
    
    @ID(custom: "ArticleID", generatedBy: .database)
    var id: Int?
    
    @Field(key: "ArticleDescription")
    var description: String
    
    @Field(key: "ArticleMark")
    var mark: String
    
    @Parent(key: "ArticleMeasureUnitID")
    var measureUnitID: MeasureUnit
    
    @Field(key: "ArticleStock")
    var stock: Double
    
    @Field(key: "ArticleState")
    var state: Bool
    
    init() {}
    
    init(id: Int? = nil, description: String, mark: String, measureUnitID: Int, stock: Double, state: Bool)
    
    {
        self.id = id
        self.description = description
        self.mark = mark
        self.$measureUnitID.id = measureUnitID
        self.stock = stock
        self.state = state
    }
}
