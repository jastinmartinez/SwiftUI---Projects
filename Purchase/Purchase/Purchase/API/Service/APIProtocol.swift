//
//  APIProtocol.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation


protocol APIProtocol {
    
    associatedtype T
    
    func getAll(completion: @escaping ([T]) -> ())
    
    func create(model: T,completion: @escaping (T) -> ())
    
    func update(model: T,completion: @escaping (Bool) -> ())
    
    func remove(model: T,completion: @escaping (Bool) -> ())
}
