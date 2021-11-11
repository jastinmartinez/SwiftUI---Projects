//
//  ArticleController.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import Foundation

class ArticleController : ObservableObject {
    
    @Published private(set) var articles = [Article]()
    
    private var articleAPI = APIService<Article>(apiResource: .Article)
    
    typealias notifyChangesToView = (Bool) -> ()
    
    init() {
        
        getAll()
    }
    
    func getAll() {
        
        articleAPI.getAll { self.articles = $0 }
    }
    
    func create(_ model: Article, notify: @escaping notifyChangesToView) {
        
        articleAPI.create(model: model) { result in
            
            if result.id != nil {
                
                self.articles.append(result)
                notify(true)
                
            }
        }
        notify(false)
    }
    
    func update(_ model: Article, notify: @escaping notifyChangesToView) {
        
        articleAPI.update(model: model) { result in
            
            if result {
                
                if let index  = self.articles.firstIndex(where: { $0.id == model.id }) {
                    
                    self.articles[index] = model
                }
            }
            notify(result)
        }
        notify(false)
    }
    
    func remove(at index: IndexSet) {
        
        for unit in index.map( { articles[$0] } )
        {
            articleAPI.remove(model: unit) { result in
                
                if result {
                    
                    self.articles.remove(atOffsets: index)
                }
            }
        }
    }
}
