//
//  AccountableSeatController.swift
//  Purchase
//
//  Created by Jastin on 11/12/21.
//

import Foundation

class AccountableSeatController: ObservableObject {
    
    @Published private(set) var auccoutableSeats = [AccoubtableSeatListResponseDetail]()
    
    init () {
        
        getAll()
    }
    
    func register(accountableSeat: AccountableSeat,completion: @escaping(Int) -> ())  {
        
        AccountableSeatAPIService(apiResource: .AccountableSeatRegister).register(accountableSeat: accountableSeat) { accountableSeatResponse in
            
            completion(accountableSeatResponse.id)
        }
    }
    
    func getAll()  {
        
        AccountableSeatAPIService(apiResource: .AccountableSeatList).getAll { AccountableSeatListRes in
            
            
            self.auccoutableSeats = AccountableSeatListRes.results.filter({$0.accountingSeatDetail.cuentaDB == "13" && $0.accountingSeatDetail.cuentaCR == "6"})
                .sorted(by: {$0.id > $1.id})
            
        }
    }
}
