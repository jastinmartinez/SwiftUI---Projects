//
//  ArticleListView.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import SwiftUI

struct ArticleListView: View {
    
    @StateObject var articleController = ArticleController()
    
    var body: some View {
        
        List {
            
            ForEach(articleController.articles, id: \.id) { article in
                NavigationLink(destination: ArticleCreateAndUpdateOperationView(articleController: articleController, article: article).navigationTitle("Modificar")) {
                    
                    ArticleView(article: article)
                }
            }
            .onDelete(perform: articleController.remove)
        }
        .refreshable { articleController.getAll() }
        .toolbar {
            NavigationLink(destination: ArticleCreateAndUpdateOperationView(articleController: articleController).navigationTitle("Nuevo")) {
                Text("Nuevo")
            }
        }
    }
}

struct ArticleListView_Previews: PreviewProvider {
    static var previews: some View {
        ArticleListView()
    }
}
