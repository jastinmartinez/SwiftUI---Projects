//
//  AirportsTests.swift
//  AirportsTests
//
//  Created by Jastin on 11/11/23.
//

import XCTest
import Airports

final class HTTPClientTests: XCTestCase {
    
    func test_client_canPerformRequest() async {
        let client = URLSessionStub()
        let baseURL = URL(string: "www.any-url.com")!
        let sut = RemoteDataSource(session: client, baseURL: baseURL, apiKey: "")
        
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
        if case let .success(data) = result {
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
            XCTAssertEqual(error.localizedDescription,
                           HTTPClientError.invalidResponse.localizedDescription)
        } else {
            XCTFail("expected success but instead go \(result)")
        }
    }
    
    func test_performAuthorizeRequestDeliversErrorOnFailRequest() async {
        let (sut, client) = makeSUT()
        
        client.completeWithFail(error: anyError())
        
        let result = await sut.perform()
        if case let .failure(error) = result {
            XCTAssertEqual(error.localizedDescription,
                           HTTPClientError.failRequest(anyError().localizedDescription).localizedDescription)
        } else {
            XCTFail("expected success but instead go \(result)")
        }
    }
    
    private func makeSUT() -> (RemoteDataSource, URLSessionStub) {
        let apiKey = anyAPIKey()
        let client = URLSessionStub()
        let sut = RemoteDataSource(session: client, baseURL: anyURL(), apiKey: apiKey)
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



final class URLSessionStub: URLSessionAdapter {
    
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
