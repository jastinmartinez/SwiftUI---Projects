//
//  AccountableSeatAPIService.swift
//  Purchase
//
//  Created by Jastin on 11/12/21.
//

import Foundation


class AccountableSeatAPIService {
    
    private var apiResource: APIResources
    
    init (apiResource: APIResources)
    {
        self.apiResource = apiResource
    }
    
    func register(accountableSeat: AccountableSeat,completion: @escaping (AccountableSeatResponse) -> ())  {
        
        try? ModelToJSON<AccountableSeat>().single(model: accountableSeat, completion: { data in
            
            APIRequest().postRequest(resource: self.apiResource, model: data, httpMethod: .POST) { data, response, error in
                
                try? JSONToModel<AccountableSeatResponse>().single(data: data, completion: completion)
            }
        })
    }
    
    func getAll(completion: @escaping (AccoubtableSeatListResponse) -> ())  {
        
        APIRequest().getRequest(resource: self.apiResource) {data,  response, error in
            
            try? JSONToModel<AccoubtableSeatListResponse>().single(data: data, completion: completion)
        }
    }
}



