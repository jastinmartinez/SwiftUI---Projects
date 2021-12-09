//
//  APIService+.swift
//  Purchase
//
//  Created by Jastin on 8/12/21.
//

import Foundation

class AuthAPIService<T: Codable>  {
    
    private(set) var apiResource: APIResources
    
    init (apiResource: APIResources)
    {
        self.apiResource = apiResource
    }
    
    func create(model: T,completion: @escaping (User) -> ())  {
        
        try? ModelToJSON<T>().single(model: model, completion: { data in
            
            APIRequest().postRequest(resource: self.apiResource, model: data, httpMethod: .POST) { data, response, error in
                
                try? JSONToModel<User>().single(data: data, completion: completion)
            }
        })
    }
}
