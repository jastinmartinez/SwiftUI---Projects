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
        
        requestSession(request: AuthorizedUrlRequest(url:  BaseURL.Purchase.appendingPathComponent(resource.rawValue), httpMethod: .GET), completion: completion)
    }
    
    func postRequest(resource: APIResources, model: Data, httpMethod: HTTPMethods,  completion: @escaping dataTaskResult) {
        
        
        if resource != .SignUp {
            
            requestSession(request: AuthorizedUrlRequest(url: BaseURL.Purchase.appendingPathComponent(resource.rawValue), httpMethod: httpMethod, body: model), completion: completion)
        }
        else {
            
            requestSession(request: UnAuthorizedUrlRequest(url: BaseURL.Purchase.appendingPathComponent(resource.rawValue), httpMethod: httpMethod, body: model), completion: completion)
        }
    }
   
    private func requestSession(request: URLRequest,completion: @escaping dataTaskResult) {
        
        URLSession.shared.dataTask(with: request) { data, response, error in DispatchQueue.main.async { completion(data,response,error) } }.resume()
    }
    
    
    private func AuthorizedUrlRequest(url: URL, httpMethod: HTTPMethods, body: Data? = nil) -> URLRequest {
        
        var request = URLRequest(url: url)
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.addValue("Basic \(UserHelper().userInfo?.key ?? "Not Authorized")", forHTTPHeaderField: "Authorization")
        
        request.httpMethod = httpMethod.rawValue
        
        if let body = body {
            
            request.httpBody = body
        }
        
        return request
    }
    
    private func UnAuthorizedUrlRequest(url: URL, httpMethod: HTTPMethods, body: Data? = nil) -> URLRequest {
        
        var request = URLRequest(url: url)
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpMethod = httpMethod.rawValue
        
        if let body = body {
            
            request.httpBody = body
        }
        
        return request
    }
}
