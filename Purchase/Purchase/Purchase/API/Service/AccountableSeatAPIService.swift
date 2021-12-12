//
//  AccountableSeatAPIService.swift
//  Purchase
//
//  Created by Jastin on 11/12/21.
//

import Foundation


class AccountableSeatAPIService {
    
    func register(accountableSeat: AccountableSeat,completion: @escaping (AccountableSeatResponse) -> ())  {
        
        try? ModelToJSON<AccountableSeat>().single(model: accountableSeat, completion: { data in
            
            APIRequest().sentData(resource: .AccountableSeatRegister, model: data, httpMethod: .POST) { data, response, error in
                
                try? JSONToModel<AccountableSeatResponse>().single(data: data, completion: completion)
            }
        })
    }
}



