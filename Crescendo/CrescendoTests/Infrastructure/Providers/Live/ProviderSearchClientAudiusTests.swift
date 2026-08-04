import Foundation
import Testing

@testable import Crescendo

struct ProviderSearchClientAudiusTests {
    @Test
    func fullRawPageAdvancesByRawRowsAfterFiltering() async throws {
        let capture = AudiusSearchRequestCapture()
        let api = AudiusAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                await capture.capture(request)
                let data = Data(
                    """
                    {
                      "data": [
                        {
                          "id": "valid",
                          "title": "Valid",
                          "duration": 120,
                          "is_streamable": true,
                          "is_stream_gated": false,
                          "user": {"name": "Artist"}
                        },
                        {
                          "id": "gated",
                          "title": "Gated",
                          "duration": 120,
                          "is_streamable": true,
                          "is_stream_gated": true,
                          "user": {"name": "Artist"}
                        }
                      ]
                    }
                    """.utf8
                )
                return (data, try Self.okResponse(for: request))
            }
        )

        let page = try await ProviderSearchClient.live(audius: api).searchPage(
            .initial(query: "signal"),
            2
        )

        #expect(page.tracks.map(\.id.nativeID) == ["valid"])
        let cursor = try #require(page.nextCursor)
        let continuation = try AudiusSearchCursor(searchCursor: cursor)
        #expect(
            continuation == AudiusSearchCursor(query: "signal", offset: 2)
        )

        let request = try #require(await capture.request)
        let url = try #require(request.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(.init(name: "limit", value: "2")))
        #expect(queryItems.contains(.init(name: "offset", value: "0")))
        #expect(await capture.requestCount == 1)
    }

    @Test
    func continuationPreservesQueryAndOffset() async throws {
        let capture = AudiusSearchRequestCapture()
        let api = AudiusAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                await capture.capture(request)
                let data = Data("{\"data\":[]}".utf8)
                return (data, try Self.okResponse(for: request))
            }
        )
        let cursor = try AudiusSearchCursor(
            query: "ambient",
            offset: 40
        ).searchCursor()

        let page = try await ProviderSearchClient.live(audius: api).searchPage(
            .continuation(cursor),
            20
        )

        #expect(page.nextCursor == nil)
        let request = try #require(await capture.request)
        let url = try #require(request.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(.init(name: "query", value: "ambient")))
        #expect(queryItems.contains(.init(name: "offset", value: "40")))
        #expect(queryItems.contains(.init(name: "limit", value: "20")))
    }

    @Test
    func shortRawPageEndsPagination() async throws {
        let api = AudiusAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                let data = Data(
                    """
                    {
                      "data": [{
                        "id": "one",
                        "title": "One",
                        "duration": 60,
                        "is_streamable": true,
                        "is_stream_gated": false
                      }]
                    }
                    """.utf8
                )
                return (data, try Self.okResponse(for: request))
            }
        )

        let page = try await ProviderSearchClient.live(audius: api).searchPage(
            .initial(query: "one"),
            20
        )

        #expect(page.tracks.count == 1)
        #expect(page.nextCursor == nil)
    }
}

private extension ProviderSearchClientAudiusTests {
    static func makeConfiguration() throws -> AudiusConfiguration {
        try #require(AudiusConfiguration(apiKey: "test-key"))
    }

    static func okResponse(for request: URLRequest) throws -> HTTPURLResponse {
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

/// Captures Audius requests so adapter-owned pagination can be asserted.
private actor AudiusSearchRequestCapture {
    private(set) var request: URLRequest?
    private(set) var requestCount = 0

    func capture(_ request: URLRequest) {
        self.request = request
        requestCount += 1
    }
}
