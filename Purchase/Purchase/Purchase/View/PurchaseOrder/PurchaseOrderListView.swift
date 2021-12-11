//
//  PurchaseOrderListView.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import SwiftUI

struct PurchaseOrderListView: View {
    
    @StateObject var articleController = PurchaseController<Article>()
    @StateObject var measureUnitController = PurchaseController<MeasureUnit>()
    @StateObject var purchaseOrderController = PurchaseController<PurchaseOrder>()
    
    fileprivate func AccountSeatProcess() {
        
        let purchaseOrders = purchaseOrderController.data.filter({ !$0.orderState })
        
        if purchaseOrders.filter({ !$0.orderState }).count > 0 {
            
            for var purchaseOrder in purchaseOrders {
                
                AccountableSeatController().register(accountableSeat: AccountableSeat(description: "Asientos Contables Compras -> \(Date.now)",auxiliar: 1, currencyCode: 1, detail: AccoutableSeatDetail(cuentaCR: "6", cuentaDB: "13", amountCR: (purchaseOrder.quantity * purchaseOrder.unitCost), amountDB: (purchaseOrder.quantity * purchaseOrder.unitCost)))) {
                    purchaseOrder.orderState = true
                    purchaseOrder.accountID = $0
                    purchaseOrderController.update(purchaseOrder){ _ in}
                }
            }
            
            refreshScreen()
        }
    }
    
    fileprivate func refreshScreen() {
        articleController.getAll()
        measureUnitController.getAll()
        purchaseOrderController.getAll()
    }
    
    var body: some View {
        
        List {
            ForEach(purchaseOrderController.data, id:\.id) { order in
                NavigationLink {
                    PurchaseOrderCreateAndUpdateView(purchaseOrderController: purchaseOrderController, articleController: articleController, measureUnitController: measureUnitController, purchaseOrder: order)
                        .navigationTitle("Modificar")
                } label: {
                    PurchaserOrderView(purchaseOrder: order,
                                       mesuare: self.measureUnitController.data.filter({$0.id == order.measureUnitID.id}).map({$0.description}).first ?? "N/A",
                                       article: self.articleController.data.filter({$0.id == order.articleID.id}).map({$0.description}).first ?? "N/A")
                }
            }
            .onDelete(perform: purchaseOrderController.remove)
        }
        .toolbar {
            
            HStack(spacing: 5) {
                NavigationLink {
                    PurchaseOrderCreateAndUpdateView(purchaseOrderController: purchaseOrderController, articleController: articleController, measureUnitController: measureUnitController)
                        .navigationTitle("Nuevo")
                } label: {
                    Text("Nuevo")
                }
                
                Button("Contabilizar") {
                    
                    AccountSeatProcess()
                }
            }
        }
        .refreshable {
            refreshScreen()
        }
    }
}

struct PurchaseOrderListView_Previews: PreviewProvider {
    static var previews: some View {
        PurchaseOrderListView()
    }
}
