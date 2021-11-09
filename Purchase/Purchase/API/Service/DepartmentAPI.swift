//
//  DepartmentAPI.swift
//  Purchase
//
//  Created by Jastin on 9/11/21.
//

import Foundation

final class DepartmentAPI {

    
    func getAll(completion: @escaping ([Department]) -> ())  {
        
        APIRequest().getRequest(resource: .Department) {data,  response, error in
            
            try? JSONToModel<Department>().array(data: data, completion: completion)
        }
    }
    
    func create(model: Department,completion: @escaping (Department) -> ())  {
        
        try? ModelToJSON<Department>().single(model: model, completion: { data in
            
            APIRequest().postRequest(resource: .Department, model: data, httpMethod: .post) { data, response, error in
                
                try? JSONToModel<Department>().single(data: data, completion: completion)
            }
        })
    }
    
    func update(model: Department,completion: @escaping (Bool) -> ())  {
        
        try? ModelToJSON<Department>().single(model: model, completion: { data in
            
            APIRequest().postRequest(resource: .Department, model: data,httpMethod: .patch) { data, response, error in
                
                guard let response = response as? HTTPURLResponse else { return }
                
                completion(response.statusCode == 200 ? true : false)
            }
        })
    }
    
    func remove(model: Department,completion: @escaping (Bool) -> ())  {
        
        try? ModelToJSON<Department>().single(model: model, completion: { data in
            
            APIRequest().postRequest(resource: .Department, model: data,httpMethod: .delete) { data, response, error in
                
                guard let response = response as? HTTPURLResponse else { return }
    
                completion(response.statusCode == 200 ? true : false)
                
            }
        })
    }
}
