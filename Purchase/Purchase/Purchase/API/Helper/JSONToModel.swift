//
//  JSONToModel.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import Foundation

final class JSONToModel<T : Decodable> {
    
    func single(data: Data?, completion: @escaping (T) -> ()) throws  {
        
        guard let data = data else { throw JSONToModelError.InvalidData }
        
        do {
            
            completion(try JSONDecoder().decode(T.self, from: data))
        }
        catch {
            
            throw JSONToModelError.InvalidModelDecode
        }
    }
    
    func array(data: Data?, completion: @escaping ([T]) -> ()) throws  {
        
        guard let data = data else { throw JSONToModelError.InvalidData }
        
        do {
            
            completion( try JSONDecoder().decode([T].self, from: data))
        }
        catch {
            
            throw JSONToModelError.InvalidModelDecode
        }
    }
}
