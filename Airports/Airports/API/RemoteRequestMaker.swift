//
//  RemoteRequestMaker.swift
//  Airports
//
//  Created by Jastin on 12/11/23.
//

import Foundation

public class RemoteRequestMaker {
    
    private let session: URLSessionAdapter
    private var baseURL: URL
    private let apiKey: String
    private var uRLQueryItems = [URLQueryItem]()
    
    public init(session: URLSessionAdapter,
                baseURL: URL,
                apiKey: String) {
        self.session = session
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
    
    public enum Error: Swift.Error {
        case invalidResponse
        case failRequest(String)
    }
    
    public func perform() async -> Result<(Data, HTTPURLResponse), Error> {
        do {
            let request = buildRequest(from: baseURL)
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.statusCode == 200 else {
                return .failure(Error.invalidResponse)
            }
            return .success((data, response))
        } catch {
            return .failure(.failRequest(error.localizedDescription))
        }
    }
    
    @discardableResult public func setParameter(with: (name: String, value: String)) -> Self {
        uRLQueryItems.append(URLQueryItem(name: with.name, value: with.value))
        return self
    }
    
    public func buildURL() {
        baseURL.append(queryItems: uRLQueryItems)
    }
    
    private func buildRequest(from url: URL) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        return request
    }
}
