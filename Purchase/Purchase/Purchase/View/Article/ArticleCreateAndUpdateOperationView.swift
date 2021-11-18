//
//  ArticleCreateAndUpdateOperationView.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import SwiftUI

struct ArticleCreateAndUpdateOperationView: View {
    
    
    @Environment(\.presentationMode) var presentation
    
    @StateObject var articleController: PurchaseController<Article>
    
    @StateObject private var measureUnit = PurchaseController<MeasureUnit>()
    
    @State var article: Article = Article(id: nil, description: "", mark: "", measureUnitID: Parent(id: nil), stock: 0.0, state: true)
    
    @State private var isCliked = false
    
    fileprivate func isOperationComplete(_ val: Bool) {
        
        if val {
            
            presentation.wrappedValue.dismiss()
        }
        
        isCliked = false
    }
    
    var body: some View {
        
        Form {
            
            Section("Articulo")
            {
                HStack {
                    
                    if article.description.isEmpty {
                        
                        RequiredMark()
                    }
                    
                    TextField("Descripcion", text: $article.description)
                }
                
                HStack {
                    
                    if article.mark.isEmpty {
                        
                        RequiredMark()
                    }
                    
                    TextField("Marca", text: $article.mark)
                }
                
                
                HStack {
                    
                    if article.measureUnitID.id == nil {
                        
                        RequiredMark()
                    }
                    
                    Picker("Unidad de Medida", selection: $article.measureUnitID.id) {
                        
                        ForEach(measureUnit.data.filter({$0.state}), id: \.id) { unit in
                            
                            Text(unit.description).tag(unit.id)
                        }
                    }
                }
                
                HStack {
                    
                    if article.stock <= 0 {
                        
                        RequiredMark()
                    }
                    
                    Text("Cantidad")
                        .foregroundColor(.secondary)
                    
                    TextField("cantidad", value: $article.stock, formatter: NumberFormatter())
                        .multilineTextAlignment(.trailing)
                }
                
                StatusPicker(status: $article.state)
                
                HStack {
                    
                    Spacer()
                    
                    if !isCliked {
                        
                        Button ("Gurdar") {
                            
                            guard !article.description.isEmpty && !article.mark.isEmpty else { return }
                            
                            guard article.measureUnitID.id != nil && article.stock > 0 else { return }
                            
                            isCliked = true
                            
                            if article.id != nil {
                                
                                articleController.update(article, notify: isOperationComplete)
                            }
                            else {
                                
                                articleController.create(article, notify: isOperationComplete)
                            }
                        }
                    }
                    else {
                        ActivityIndicator(isAnimating: $isCliked, style: .medium)
                    }
                }
            }
        }
    }
}

struct ArticleCreateAndUpdateOperationView_Previews: PreviewProvider {
    static var previews: some View {
        ArticleCreateAndUpdateOperationView(articleController: PurchaseController<Article>())
    }
}
