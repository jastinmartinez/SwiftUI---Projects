//
//  PurchaseOrderListView.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import SwiftUI

struct PurchaseOrderListView: View {
    
    @StateObject var articleController = ArticleController()
    @StateObject var measureUnitController = MeasureUnitController()
    @StateObject var purchaseOrderController = PurchaseOrderController()
    
    var body: some View {
        
        List {
            ForEach(purchaseOrderController.purchaseOrders, id:\.id) { order in
                NavigationLink {
                    PurchaseOrderCreateAndUpdateView(purchaseOrderController: purchaseOrderController, articleController: articleController, measureUnitController: measureUnitController, purchaseOrder: order)
                        .navigationTitle("Modificar")
                } label: {
                    PurchaserOrderView(purchaseOrder: order,
                                       mesuare: self.measureUnitController.measureUnits.filter({$0.id == order.measureUnitID.id}).map({$0.description}).first ?? "N/A",
                                       article: self.articleController.articles.filter({$0.id == order.articleID.id}).map({$0.description}).first ?? "N/A")
                }
            }
            .onDelete(perform: purchaseOrderController.remove)
        }
        .toolbar {
            NavigationLink {
                PurchaseOrderCreateAndUpdateView(purchaseOrderController: purchaseOrderController, articleController: articleController, measureUnitController: measureUnitController)
                    .navigationTitle("Nuevo")
            } label: {
                Text("Nuevo")
            }
        }
        .refreshable {
            articleController.getAll()
            measureUnitController.getAll()
            purchaseOrderController.getAll()
        }
    }
}

struct PurchaseOrderListView_Previews: PreviewProvider {
    static var previews: some View {
        PurchaseOrderListView()
    }
}
