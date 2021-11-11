//
//  MeasureUnitAPI.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation


 class APIService<E : Codable>: APIProtocol
{
    
     private (set) var apiResource: APIResources
     
     typealias T = E
     
     
     init (apiResource: APIResources)
     {
         self.apiResource = apiResource
     }
    
    func getAll(completion: @escaping ([T]) -> ())  {
        
        APIRequest().getRequest(resource: self.apiResource) {data,  response, error in
            
            try? JSONToModel<T>().array(data: data, completion: completion)
        }
    }
    
    func create(model: T,completion: @escaping (T) -> ())  {
        
        try? ModelToJSON<T>().single(model: model, completion: { data in
            
            APIRequest().postRequest(resource: self.apiResource, model: data, httpMethod: .POST) { data, response, error in
                
                try? JSONToModel<T>().single(data: data, completion: completion)
            }
        })
    }
    
    func update(model: T,completion: @escaping (Bool) -> ())  {
        
        try? ModelToJSON<T>().single(model: model, completion: { data in
            
            APIRequest().postRequest(resource: self.apiResource, model: data,httpMethod: .PATCH) { data, response, error in
                
                guard let response = response as? HTTPURLResponse else { return }
                
                completion(response.statusCode == 200 ? true : false)
            }
        })
    }
    
    func remove(model: T,completion: @escaping (Bool) -> ())  {
        
        try? ModelToJSON<T>().single(model: model, completion: { data in
            
            APIRequest().postRequest(resource: self.apiResource, model: data,httpMethod: .DELETE) { data, response, error in
                
                guard let response = response as? HTTPURLResponse else { return }
    
                completion(response.statusCode == 200 ? true : false)
                
            }
        })
    }
}
