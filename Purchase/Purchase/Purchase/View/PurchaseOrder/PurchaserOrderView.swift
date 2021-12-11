//
//  PurchaserOrderView.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import SwiftUI

struct PurchaserOrderView: View {
    
    var purchaseOrder: PurchaseOrder
    
    var mesuare: String
    
    var article: String
    
    var body: some View {
        
        VStack {
            
            HStack {
                Spacer()
                LogoView(name: "purchaseorder")
            }
            
            HStack(spacing: 20) {
            
                Text("\(purchaseOrder.id!)")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
                
                HStack {
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(purchaseOrder.orderDate)
                        Text(purchaseOrder.orderNumber)
                        Text(article)
                        Text(mesuare)
                        Text("\(purchaseOrder.quantity, specifier: "%.2f")")
                        Text("\(purchaseOrder.unitCost, specifier: "%.2f")")
                        if purchaseOrder.orderState {
                            
                            Text("Contabilizada No.(\(purchaseOrder.accountID))")
                                .foregroundColor(.blue)
                        }
                        else {
                            Text("No Contabilizada")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
}

struct PurchaserOrderView_Previews: PreviewProvider {
    static var previews: some View {
        PurchaserOrderView(purchaseOrder: PurchaseOrder(id: 1, orderNumber: "0001", orderDate: Date.now.formatted(date: .abbreviated, time: .omitted), articleID: Parent(id: 1), quantity: 1, measureUnitID: Parent(id: 1), unitCost: 10, orderState: false, accountID: 0), mesuare: "Kilo",article: "Avon")
    }
}
