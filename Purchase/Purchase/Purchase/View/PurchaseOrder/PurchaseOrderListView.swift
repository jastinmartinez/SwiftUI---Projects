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
    @State private var istherePendingPurchasesOrderToSend: Bool = false
    
    private var accountableSeatController: AccountableSeatController = AccountableSeatController()
    
    fileprivate func MarkAndSentPurchaseOrderToAccounting() {
        
        accountableSeatController.registerPurchaserOrderToAccounting(purchaseOrderController: purchaseOrderController) { _istherePendingPurchasesOrderToSend in
            
            istherePendingPurchasesOrderToSend = _istherePendingPurchasesOrderToSend
            
            if _istherePendingPurchasesOrderToSend {
                
                refreshScreen()
            }
          
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
                    
                     MarkAndSentPurchaseOrderToAccounting()
                    
                }.alert("No hay transacciones disponibles para contabilizar",isPresented: $istherePendingPurchasesOrderToSend) {
                    
                    Button("Ok", role: .cancel) {}
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
