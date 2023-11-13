//
//  AirportsTests.swift
//  AirportsTests
//
//  Created by Jastin on 11/11/23.
//

import XCTest


protocol URLSessionAdapter {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

private class HTTPClient {
    
    private let session: URLSessionAdapter
    private var baseURL: URL
    private let apiKey: String
    private var uRLQueryItems = [URLQueryItem]()
    
    init(session: URLSessionAdapter,
         baseURL: URL,
         apiKey: String) {
        self.session = session
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
    
    enum Error: Swift.Error, Equatable {
        case invalidResponse
        case failRequest(String)
    }
    
    func perform() async -> Result<(Data, HTTPURLResponse), Error> {
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
    
    @discardableResult func setParameter(with: (name: String, value: String)) -> Self {
        uRLQueryItems.append(URLQueryItem(name: with.name, value: with.value))
        return self
    }
    
    func buildURL() {
        baseURL.append(queryItems: uRLQueryItems)
    }
    
    private func buildRequest(from url: URL) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        return request
    }
}

final class HTTPClientTests: XCTestCase {
    
    func test_client_canPerformRequest() async {
        let client = MockURLSession()
        let baseURL = URL(string: "www.any-url.com")!
        let sut = HTTPClient(session: client, baseURL: baseURL, apiKey: "")
        
        let _ = await  sut.perform()
        
        XCTAssertEqual(client.urlRequests.count, 1)
    }
    
    func test_client_canPerformAuthorizeRequest() async {
        let (sut, client) = makeSUT()
        
        let _ = await  sut.perform()
        
        var expectedRequest = URLRequest(url: anyURL())
        expectedRequest.setValue(anyAPIKey(), forHTTPHeaderField: "X-Api-Key")
        
        XCTAssertEqual(client.urlRequests, [expectedRequest])
    }
    
    func test_client_canPerformAuthorizeRequestWithParameter() async {
        let (sut, client) = makeSUT()
        let expectedPath = "www.any-url.com?name=Jastin"
        
        sut.setParameter(with: ("name", "Jastin"))
        sut.buildURL()
        let _ = await  sut.perform()
        
        XCTAssertEqual(expectedPath, client.urlRequests.first?.url?.absoluteString)
    }
    
    func test_client_canPerformAuthorizeRequestWithMultipleParameter() async {
        let (sut, client) = makeSUT()
        let expectedPath = "www.any-url.com?name=Heathrow&city=London"
        
        sut.setParameter(with: ("name", "Heathrow"))
            .setParameter(with: ("city", "London"))
        sut.buildURL()
        let _ = await sut.perform()
        
        XCTAssertEqual(expectedPath, client.urlRequests.first?.url?.absoluteString)
    }
    
    func test_performAuthorizeRequestDeliversDataOn200Response() async {
        let (sut, client) = makeSUT()
        let statusCode = 200
        let mockData = Data()
        
        client.completeWithData(for: anyURL(), data: mockData, statusCode: statusCode)
        
        let result = await sut.perform()
        if case let .success((data, response)) = result {
            XCTAssertEqual(response.statusCode, statusCode)
            XCTAssertEqual(data, mockData)
        } else {
            XCTFail("expected success but instead go \(result)")
        }
    }
    
    func test_performAuthorizeRequestDeliversErrorOnInvalidCode() async {
        let (sut, client) = makeSUT()
        let statusCode = 404
        let mockData = Data("wrong json".utf8)
        
        client.completeWithData(for: anyURL(), data: mockData, statusCode: statusCode)
        
        let result = await sut.perform()
        if case let .failure(error) = result {
            XCTAssertEqual(error, .invalidResponse)
        } else {
            XCTFail("expected success but instead go \(result)")
        }
    }
    
    func test_performAuthorizeRequestDeliversErrorOnFailRequest() async {
        let (sut, client) = makeSUT()
        
        client.completeWithFail(error: anyError())
        
        let result = await sut.perform()
        if case let .failure(error) = result {
            XCTAssertEqual(error, .failRequest(anyError().localizedDescription))
        } else {
            XCTFail("expected success but instead go \(result)")
        }
    }
    
    private func makeSUT() -> (HTTPClient, MockURLSession) {
        let apiKey = anyAPIKey()
        let client = MockURLSession()
        let sut = HTTPClient(session: client, baseURL: anyURL(), apiKey: apiKey)
        return (sut, client)
    }
    
    private func anyURL() -> URL {
        return URL(string: "www.any-url.com")!
    }
    
    private func anyAPIKey() -> String {
        return "apiKey"
    }
    
    private func anyError() -> Error {
        return NSError(domain: "any error", code: 0)
    }
}


extension URLSession: URLSessionAdapter {}


final class MockURLSession: URLSessionAdapter {
    
    private(set) var urlRequests = [URLRequest]()
    private var dataResult: Result<(Data, URLResponse), Error> = .success((Data(), URLResponse()))
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        urlRequests.append(request)
        switch dataResult {
        case let .success((data, response)):
            return (data, response)
        case let .failure(error):
            throw error
        }
    }
    
    func completeWithData(for url: URL, data: Data, statusCode: Int) {
        let urlResponse = HTTPURLResponse(url: url,
                                          statusCode: statusCode,
                                          httpVersion: nil,
                                          headerFields: nil)!
        dataResult = .success((data, urlResponse))
    }
    
    func completeWithFail(error: Error) {
        dataResult = .failure(error)
    }
}
