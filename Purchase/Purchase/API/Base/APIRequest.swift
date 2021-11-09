//
//  APIService.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import Foundation
import SwiftUI



final class APIRequest {
    
    typealias dataTaskResult = ((Data?, URLResponse?,Error?) -> ())
    
    func getRequest(resource: APIResources,completion: @escaping dataTaskResult) {
        
        requestSession(request: urlRequest(url:  BaseURL.Purchase.appendingPathComponent(resource.rawValue), httpMethod: .get), completion: completion)
    }
    
    func postRequest(resource: APIResources, model: Data, httpMethod: HTTPMethods,  completion: @escaping dataTaskResult) {
        
        requestSession(request: urlRequest(url: BaseURL.Purchase.appendingPathComponent(resource.rawValue), httpMethod: httpMethod, body: model), completion: completion)
    }
    
    private func requestSession(request: URLRequest,completion: @escaping dataTaskResult) {
        
        URLSession.shared.dataTask(with: request) { data, response, error in DispatchQueue.main.async { completion(data,response,error) } }.resume()
    }
    
    private func urlRequest(url: URL, httpMethod: HTTPMethods, body: Data? = nil) -> URLRequest {
        
        var request = URLRequest(url: url)
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpMethod = httpMethod.rawValue
        
        if let body = body {
            
            request.httpBody = body
        }
        
        return request
    }
}
