//
//  APIProtocol.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation


protocol APIProtocol {
    
  associatedtype T
    
  associatedtype W
    
    func getAll(completion: @escaping ([W]) -> ())
    
    func create(model: T,completion: @escaping (W) -> ())
    
    func update(model: T,completion: @escaping (Bool) -> ())
    
    func remove(model: T,completion: @escaping (Bool) -> ())
}

