import Foundation
import Testing

@testable import Crescendo

struct ProviderSearchClientJamendoTests {
    @Test
    func nextCursorIsNilWhenOffsetAndResultsReachFullCount() async throws {
        let fixtureData = Data(
            Self.fixtureJSON(resultsFullCount: 1, trackCount: 1).utf8
        )
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in (fixtureData, try Self.okResponse(for: request)) }
        )
        let client = ProviderSearchClient.live(jamendo: api)

        let page = try await client.searchPage(.initial(query: "x"), 10)

        #expect(page.tracks.count == 1)
        #expect(page.nextCursor == nil)
    }

    @Test
    func continuationPreservesQueryAndAdvancesOffset() async throws {
        let fixtureData = Data(
            Self.fixtureJSON(resultsFullCount: 100, trackCount: 5).utf8
        )
        let capturedRequest = RequestCapture()
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                await capturedRequest.capture(request)
                return (fixtureData, try Self.okResponse(for: request))
            }
        )
        let client = ProviderSearchClient.live(jamendo: api)
        let cursor = try JamendoSearchCursor(query: "jazz", offset: 20).searchCursor()

        let page = try await client.searchPage(.continuation(cursor), 5)

        let request = try #require(await capturedRequest.request)
        let url = try #require(request.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(URLQueryItem(name: "search", value: "jazz")))
        #expect(queryItems.contains(URLQueryItem(name: "offset", value: "20")))

        let nextCursor = try #require(page.nextCursor)
        let nextContinuation = try JamendoSearchCursor(searchCursor: nextCursor)
        #expect(nextContinuation.query == "jazz")
        #expect(nextContinuation.offset == 25)
    }

    @Test
    func exactReducerLimitReachesJamendoAPI() async throws {
        let fixtureData = Data(
            Self.fixtureJSON(resultsFullCount: 1, trackCount: 1).utf8
        )
        let capturedRequest = RequestCapture()
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                await capturedRequest.capture(request)
                return (fixtureData, try Self.okResponse(for: request))
            }
        )
        let client = ProviderSearchClient.live(jamendo: api)

        _ = try await client.searchPage(.initial(query: "x"), 37)

        let request = try #require(await capturedRequest.request)
        let url = try #require(request.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(URLQueryItem(name: "limit", value: "37")))
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

    private static func fixtureJSON(resultsFullCount: Int, trackCount: Int) -> String {
        let results = (0..<trackCount)
            .map { index in
                """
                {
                  "id": "\(index)",
                  "name": "Track \(index)",
                  "artist_name": "Artist \(index)",
                  "album_name": "Album \(index)",
                  "image": "https://example.com/artwork\(index).jpg",
                  "duration": "180",
                  "audio": "https://example.com/audio\(index).mp3"
                }
                """
            }
            .joined(separator: ",")
        return """
            {
              "headers": {
                "status": "success",
                "code": 0,
                "results_count": \(trackCount),
                "results_fullcount": \(resultsFullCount)
              },
              "results": [\(results)]
            }
            """
    }
}

/// Captures the `URLRequest` a `@Sendable` HTTP closure receives, for assertion after the call.
private actor RequestCapture {
    private(set) var request: URLRequest?

    func capture(_ request: URLRequest) {
        self.request = request
    }
}
