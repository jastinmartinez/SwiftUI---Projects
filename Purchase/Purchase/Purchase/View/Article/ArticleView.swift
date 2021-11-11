//
//  ArticleView.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import SwiftUI

struct ArticleView: View {
    
    var article: Article
    
    var measureUnit: String
    
    var body: some View {
        VStack {
            
            HStack {
                Spacer()
                LogoView(name: "article")
            }
            
            HStack(spacing: 20) {
            
                Text("\(article.id!)")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
                
                HStack {
                    Spacer()
                    VStack(alignment: .trailing) {
                        
                        Text(article.description)
                        Text(article.mark)
                        Text(measureUnit)
                        Text("\(article.stock,specifier: "%.2f")")
                        Text(article.state.toString())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct ArticleView_Previews: PreviewProvider {
    static var previews: some View {
        ArticleView(article: Article(id: 1, description: "Ejmplo", mark: "a", measureUnitID: Parent(id: 1), stock: 20, state: true),measureUnit: "Gramo")
    }
}
