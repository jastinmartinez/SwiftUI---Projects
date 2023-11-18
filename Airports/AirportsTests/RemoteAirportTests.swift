//
//  RemoteAirportTests.swift
//  AirportsTests
//
//  Created by Jastin on 12/11/23.
//

import Foundation
import XCTest
import Airports


struct Airport: Decodable {
    var icao: String
    var iata: String
    var name: String
    var city: String
    var region: String
    var country: String
    var elevation_ft: String
    var latitude: String
    var longitude: String
    var timezone: String
}

public class RemoteAirport {
    
    private let client: HTTPClient
    
    init(client: HTTPClient) {
        self.client = client
    }
    
    func getTopAirpots() async -> Result<[Airport], Error> {
        switch await client.perform() {
        case let .success(data):
            guard let airports = try? JSONDecoder().decode([Airport].self, from: data) else {
                return .failure(.invalidData)
            }
            return .success(airports)
        case let .failure(error):
            return .failure(.map(error))
        }
    }
}

extension RemoteAirport {
    enum Error: Swift.Error {
        case invalidData
        case dataNotAvailable
        case network
        
        static func map(_ error: HTTPClientError) -> Self {
            switch error {
            case .invalidResponse:
                return .dataNotAvailable
            case .failRequest(let reason):
                print(">> FAIL REQUEST REASON: \(reason)")
                return .network
            }
        }
    }
}

final class RemoteAirportTests: XCTestCase {
    
    func test_getTopAirpots_DeliversSuccessWithData() async {
        let topAirportData = setData(for: topAirports())
        let datasource = RemoteDataSourceStub(result: .success(topAirportData))
        let sut = RemoteAirport(client: datasource)
        
        let result =  await sut.getTopAirpots()
        
        if case .success(let success) = result {
            XCTAssertFalse(success.isEmpty)
            XCTAssertEqual(success.count, 3)
        } else {
            XCTFail("expected success but instead got \(result)")
        }
    }
    
    func test_getTopAirpots_DeliversFailureWithInvalidData() async {
        let invalidData = setData(for: invalidData())
        let datasource = RemoteDataSourceStub(result: .success(invalidData))
        let sut = RemoteAirport(client: datasource)
        
        let result =  await sut.getTopAirpots()
        
        if case .failure(let error) = result {
            XCTAssertEqual(error, RemoteAirport.Error.invalidData)
        } else {
            XCTFail("expected failure but instead got \(result)")
        }
    }
    
    func test_getTopAirpots_DeliversFailureForInvalidResponse() async {
        let invalidData = setData(for: invalidData())
        let datasource = RemoteDataSourceStub(result: .failure(.invalidResponse))
        let sut = RemoteAirport(client: datasource)
        
        let result =  await sut.getTopAirpots()
        
        if case .failure(let error) = result {
            XCTAssertEqual(error, RemoteAirport.Error.dataNotAvailable)
        } else {
            XCTFail("expected failure but instead got \(result)")
        }
    }
    
    func test_getTopAirpots_DeliversFailureForFailRequest() async {
        let invalidData = setData(for: invalidData())
        let datasource = RemoteDataSourceStub(result: .failure(.failRequest("some error")))
        let sut = RemoteAirport(client: datasource)
        
        let result =  await sut.getTopAirpots()
        
        if case .failure(let error) = result {
            XCTAssertEqual(error, RemoteAirport.Error.network)
        } else {
            XCTFail("expected failure but instead got \(result)")
        }
    }
    
    private func anyURL() -> URL {
        return URL(string: "www.any-url.com")!
    }
    
    private func anyAPIKey() -> String {
        return "apiKey"
    }
    
    private func setData(for jsonString: String) -> Data {
        return Data(jsonString.utf8)
    }
    
    private func invalidData() -> String {
        return "[dkk-/djj]"
    }
    
    private func topAirports() -> String {
        """
        [
        {
            "icao": "EGLL",
            "iata": "LHR",
            "name": "London Heathrow Airport",
            "city": "London",
            "region": "England",
            "country": "GB",
            "elevation_ft": "83",
            "latitude": "51.4706001282",
            "longitude": "-0.4619410038",
            "timezone": "Europe/London"
        },
        {
            "icao": "EGLL",
            "iata": "LHR",
            "name": "London Heathrow Airport",
            "city": "London",
            "region": "England",
            "country": "GB",
            "elevation_ft": "83",
            "latitude": "51.4706001282",
            "longitude": "-0.4619410038",
            "timezone": "Europe/London"
        },
        {
            "icao": "EGLL",
            "iata": "LHR",
            "name": "London Heathrow Airport",
            "city": "London",
            "region": "England",
            "country": "GB",
            "elevation_ft": "83",
            "latitude": "51.4706001282",
            "longitude": "-0.4619410038",
            "timezone": "Europe/London"
        }
        ]
        """
    }
    
    private class RemoteDataSourceStub: HTTPClient {
        private let result: Result<Data, HTTPClientError>
        
        init(result: Result<Data, HTTPClientError>) {
            self.result = result
        }
        
        func perform() async -> Result<Data, Airports.HTTPClientError> {
            return result
        }
    }
}
