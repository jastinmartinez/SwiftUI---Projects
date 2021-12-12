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
    
    func retrieveData(resource: APIResources,completion: @escaping dataTaskResult) {
        
        let apiResourceHandler  = ApiResourceReturnResourceType(apiResource: resource)
        
        if apiResourceHandler ==  .AccountableSeatIntegration {
            
            urlSession(request: urlRequest(url:  BaseURL.AccountableSeat.appendingPathComponent(resource.rawValue), httpMethod: .GET, apiResourceType: apiResourceHandler), completion: completion)
        }
        else  {
            urlSession(request: urlRequest(url:  BaseURL.Purchase.appendingPathComponent(resource.rawValue), httpMethod: .GET, apiResourceType: apiResourceHandler), completion: completion)
        }
    }
    
    func sentData(resource: APIResources, model: Data, httpMethod: HTTPMethods,  completion: @escaping dataTaskResult) {
        
        
        let apiResourceHandler  = ApiResourceReturnResourceType(apiResource: resource)
        
        if apiResourceHandler ==  .AccountableSeatIntegration {
            
            urlSession(request: urlRequest(url: BaseURL.AccountableSeat.appendingPathComponent(resource.rawValue), httpMethod: httpMethod, body: model, apiResourceType: apiResourceHandler) , completion: completion)
        }
        else {
            
            urlSession(request: urlRequest(url: BaseURL.Purchase.appendingPathComponent(resource.rawValue), httpMethod: httpMethod, body: model, apiResourceType: apiResourceHandler) , completion: completion)
        }
    }
    
    private func urlSession(request: URLRequest,completion: @escaping dataTaskResult) {
        
        URLSession.shared.dataTask(with: request) { data, response, error in DispatchQueue.main.async { completion(data,response,error) } }.resume()
    }
    
    private func urlRequest(url: URL, httpMethod: HTTPMethods, body: Data? = nil, apiResourceType: APIResourceType) -> URLRequest {
   
        var request = URLRequest(url: url)
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if apiResourceType == .Authorized {
            
            request.addValue("Basic \(UserHelper().userInfo?.key ?? "Not Authorized")", forHTTPHeaderField: "Authorization")
        }
        
        request.httpMethod = httpMethod.rawValue
        
        if let body = body {
            
            request.httpBody = body
        }
        
        return request
    }
    
    private func ApiResourceReturnResourceType(apiResource: APIResources) -> APIResourceType {
        
        switch apiResource {
        case .Department:
            return .Authorized
        case .Article:
            return .Authorized
        case .PurchaseOrder:
            return .Authorized
        case .MeasureUnit:
            return .Authorized
        case .Provider:
            return .Authorized
        case .SignIn:
            return .Authorized
        case .SignUp:
            return .UnAuthorized
        case .AccountableSeatList:
            return .AccountableSeatIntegration
        case .AccountableSeatRegister:
            return .AccountableSeatIntegration
        }
    }
    
    private enum APIResourceType {
        
        case Authorized
        
        case UnAuthorized
        
        case AccountableSeatIntegration
    }
    
}
