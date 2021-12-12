//
//  AccountableSeatController.swift
//  Purchase
//
//  Created by Jastin on 11/12/21.
//

import Foundation

class AccountableSeatController {
    
    func registerPurchaserOrderToAccounting(purchaseOrderController: PurchaseController<PurchaseOrder>, istherePendingPurchaseOrder: @escaping (Bool) -> ())  {
        
        let purchaseOrders = purchaseOrderController.data.filter({ !$0.orderState })
        
        let istherePendingPurchasesOrderToSend = purchaseOrders.filter({ !$0.orderState }).count == 0
        
        istherePendingPurchaseOrder(istherePendingPurchasesOrderToSend)
        
        guard !istherePendingPurchasesOrderToSend else { return }
        
        for var purchaseOrder in purchaseOrders {
            
            AccountableSeatAPIService().register(accountableSeat: AccountableSeat(detail: AccoutableSeatDetail(amountCR: purchaseOrder.orderAmount, amountDB: purchaseOrder.orderAmount))) { accountSeatResponse in
                
                purchaseOrder.orderState = accountSeatResponse.id > 0
                
                purchaseOrder.accountID = accountSeatResponse.id
                
                purchaseOrderController.update(purchaseOrder){ _ in}
            }
        }
    }
}

