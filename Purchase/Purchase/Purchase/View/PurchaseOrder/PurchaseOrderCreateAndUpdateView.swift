//
//  PurchaseOrderCreateAndUpdateView.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import SwiftUI

struct PurchaseOrderCreateAndUpdateView: View {
    
    
    @Environment(\.presentationMode) var presentation
    
    @StateObject var purchaseOrderController: PurchaseController<PurchaseOrder>
    
    @StateObject var articleController: PurchaseController<Article>
    
    @StateObject var measureUnitController: PurchaseController<MeasureUnit>
    
    @State private var date: Date = .now
    
    @State var purchaseOrder: PurchaseOrder =  PurchaseOrder(id: nil, orderNumber: "", orderDate: Date.now.formatted(date: .abbreviated, time: .omitted) , articleID: Parent(id: nil), quantity: 0.0, measureUnitID: Parent(id: nil), unitCost: 0.0)
    
    @State var isCliked = false
    
    fileprivate func isOperationComplete(_ isComplete: Bool) {
        
        if isComplete {
            presentation.wrappedValue.dismiss()
            isCliked = false
        }
    }
    
    fileprivate func setDateFormatWhenModify() {
        
        if purchaseOrder.id != nil {
            
            let formatter = DateFormatter()
            
            formatter.dateFormat = "MMM d, yyyy"
            
            date = formatter.date(from: purchaseOrder.orderDate) ?? .now
        }
    }
    
    
    var body: some View {
        
        Form {
            
            Section("Order de compra") {
                
                HStack {
                    
                    if purchaseOrder.orderNumber.isEmpty {
                        
                        RequiredMark()
                    }
                    
                    TextField("No. de ordern", text: $purchaseOrder.orderNumber)
                }
                
                DatePicker("Fecha", selection: $date,displayedComponents: .date)
                    .onChange(of: date) { purchaseOrder.orderDate = $0.formatted(date: .abbreviated, time: .omitted) }
                
                HStack {
                    
                    if purchaseOrder.measureUnitID.id == nil {
                        
                        RequiredMark()
                    }
                    Picker("Unidades de Medida", selection: $purchaseOrder.measureUnitID.id) {
                        
                        ForEach(measureUnitController.data.filter({$0.state}), id: \.id) { unit in
                            
                            Text(unit.description).tag(unit.id)
                        }
                    }
                }
                HStack {
                    
                    if purchaseOrder.articleID.id == nil {
                        
                        RequiredMark()
                    }
                    
                    Picker("Articulos", selection: $purchaseOrder.articleID.id) {
                        
                        ForEach(articleController.data.filter({$0.state}), id: \.id) { article in
                            
                            Text(article.description).tag(article.id)
                        }
                    }
                }
                
                HStack {
                    
                    if purchaseOrder.quantity <= 0 {
                        
                        RequiredMark()
                    }
                    
                    HStack {
                        Text("Cantidad")
                            .foregroundColor(.secondary)
                        TextField("Cantidad", value: $purchaseOrder.quantity,formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                HStack {
                    
                    if purchaseOrder.unitCost <= 0 {
                        
                        RequiredMark()
                    }
                    
                    HStack {
                        Text("Costo Unitario $")
                            .foregroundColor(.secondary)
                        TextField("Costo Unitario", value: $purchaseOrder.unitCost,formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if !isCliked {
                    HStack {
                        Spacer()
                        Button("Guardar") {
                            
                            guard !purchaseOrder.orderNumber.isEmpty && purchaseOrder.measureUnitID.id != nil else { return }
                            
                            guard purchaseOrder.articleID.id != nil && purchaseOrder.quantity > 0 else { return }
                            
                            guard purchaseOrder.unitCost > 0 else { return }
                            
                            isCliked = true
                            
                            if purchaseOrder.id != nil {
                                
                                purchaseOrderController.update(purchaseOrder, notify: isOperationComplete)
                            }
                            else {
                                
                                purchaseOrderController.create(purchaseOrder, notify: isOperationComplete)
                            }
                        }
                    }
                }
                else {
                    ActivityIndicator(isAnimating: $isCliked, style: .medium)
                }
            }
        }
        .onAppear {
            
            setDateFormatWhenModify()
        }
    }
}

struct PurchaseOrderCreateAndUpdateView_Previews: PreviewProvider {
    static var previews: some View {
        PurchaseOrderCreateAndUpdateView(purchaseOrderController: PurchaseController<PurchaseOrder>(),
                                         articleController: PurchaseController<Article>(), measureUnitController: PurchaseController<MeasureUnit>())
    }
}
