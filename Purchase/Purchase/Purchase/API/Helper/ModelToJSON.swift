//
//  ModelToJSON.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import Foundation

final class ModelToJSON<T : Encodable> {
    
    func single(model: T, completion: @escaping (Data) -> ()) throws  {
        
        do {
            
            completion(try JSONEncoder().encode(model))
        }
        catch {
            
            throw ModelToJSONError.InvalidModelEncode
        }
    }
}
