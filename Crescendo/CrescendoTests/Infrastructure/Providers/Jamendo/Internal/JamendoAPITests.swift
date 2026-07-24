import Foundation
import Testing

@testable import Crescendo

struct JamendoAPITests {
    private static let fixtureJSON = """
        {
          "headers": {
            "status": "success",
            "code": 0,
            "results_count": 1,
            "results_fullcount": 41
          },
          "results": [
            {
              "id": "42",
              "name": "Signal",
              "artist_name": "The Tests",
              "album_name": "Assertions",
              "image": "https://example.com/artwork.jpg",
              "duration": "180",
              "audio": "https://example.com/audio.mp3"
            }
          ]
        }
        """

    @Test
    func tracksSendsExactQueryItemsAndDecodesResponse() async throws {
        let fixtureData = Data(Self.fixtureJSON.utf8)
        let capturedRequest = RequestCapture()

        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                await capturedRequest.capture(request)
                return (fixtureData, try Self.okResponse(for: request))
            }
        )

        let result = try await api.tracks(query: "jazz", offset: 20, limit: 25)

        #expect(result.headers.status == "success")
        #expect(result.headers.resultsCount == 1)
        #expect(result.headers.resultsFullCount == 41)
        #expect(result.results.first?.id == "42")
        #expect(result.results.first?.name == "Signal")
        #expect(result.results.first?.artistName == "The Tests")
        #expect(result.results.first?.albumName == "Assertions")
        #expect(result.results.first?.image == "https://example.com/artwork.jpg")
        #expect(result.results.first?.duration == "180")
        #expect(result.results.first?.audio == "https://example.com/audio.mp3")

        let request = try #require(await capturedRequest.request)
        let url = try #require(request.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let queryItems = try #require(components.queryItems)

        #expect(queryItems.contains(URLQueryItem(name: "client_id", value: "test-client")))
        #expect(queryItems.contains(URLQueryItem(name: "search", value: "jazz")))
        #expect(queryItems.contains(URLQueryItem(name: "offset", value: "20")))
        #expect(queryItems.contains(URLQueryItem(name: "limit", value: "25")))
        #expect(queryItems.contains(URLQueryItem(name: "format", value: "json")))
        #expect(queryItems.contains(URLQueryItem(name: "audioformat", value: "mp32")))
        #expect(queryItems.contains(URLQueryItem(name: "imagesize", value: "300")))
        #expect(queryItems.contains(URLQueryItem(name: "type", value: "single albumtrack")))
        #expect(queryItems.contains(URLQueryItem(name: "fullcount", value: "true")))
    }

    @Test
    func trackSendsExactQueryItemsAndReturnsFirstResult() async throws {
        let fixtureData = Data(Self.fixtureJSON.utf8)
        let capturedRequest = RequestCapture()

        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                await capturedRequest.capture(request)
                return (fixtureData, try Self.okResponse(for: request))
            }
        )

        let track = try await api.track(id: "42")

        #expect(track.id == "42")
        #expect(track.name == "Signal")

        let request = try #require(await capturedRequest.request)
        let url = try #require(request.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let queryItems = try #require(components.queryItems)

        #expect(queryItems.contains(URLQueryItem(name: "client_id", value: "test-client")))
        #expect(queryItems.contains(URLQueryItem(name: "id", value: "42")))
        #expect(queryItems.contains(URLQueryItem(name: "limit", value: "1")))
        #expect(queryItems.contains(URLQueryItem(name: "format", value: "json")))
        #expect(queryItems.contains(URLQueryItem(name: "audioformat", value: "mp32")))
        #expect(queryItems.contains(URLQueryItem(name: "imagesize", value: "300")))
    }

    @Test
    func trackThrowsUnavailableWhenResultsAreEmpty() async throws {
        let emptyResultsJSON = """
            {
              "headers": {
                "status": "success",
                "code": 0,
                "results_count": 0,
                "results_fullcount": 0
              },
              "results": []
            }
            """
        let fixtureData = Data(emptyResultsJSON.utf8)

        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                (fixtureData, try Self.okResponse(for: request))
            }
        )

        await #expect(throws: MusicProviderError.unavailable) {
            try await api.track(id: "missing")
        }
    }

    @Test
    func tracksThrowsNetworkErrorOnNonSuccessStatusCode() async throws {
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                let url = try #require(request.url)
                let response = try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 500,
                        httpVersion: nil,
                        headerFields: nil
                    )
                )
                return (Data(), response)
            }
        )

        await #expect(throws: MusicProviderError.network) {
            try await api.tracks(query: "jazz", offset: 0, limit: 10)
        }
    }

    @Test
    func tracksThrowsNetworkErrorOnUndecodableResponseBody() async throws {
        let malformedData = Data("not valid json at all".utf8)

        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                (malformedData, try Self.okResponse(for: request))
            }
        )

        await #expect(throws: MusicProviderError.network) {
            try await api.tracks(query: "jazz", offset: 0, limit: 10)
        }
    }

    // MARK: - Helpers

    private static func makeConfiguration() throws -> JamendoConfiguration {
        try #require(JamendoConfiguration(clientID: "test-client"))
    }

    private static func okResponse(for request: URLRequest) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
    }
}

/// Captures the `URLRequest` a `@Sendable` HTTP closure receives, for assertion after the call.
private actor RequestCapture {
    private(set) var request: URLRequest?

    func capture(_ request: URLRequest) {
        self.request = request
    }
}
