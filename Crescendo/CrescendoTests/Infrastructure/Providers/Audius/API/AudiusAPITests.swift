import Foundation
import Testing

@testable import Crescendo

struct AudiusAPITests {
    @Test
    func tracksBuildsExpectedRequestAndDecodesResponse() async throws {
        let capture = AudiusRequestCapture()
        let fixture = Data(
            """
            {
              "data": [{
                "id": "audius-42",
                "title": "Signal",
                "duration": 180,
                "is_streamable": true,
                "is_stream_gated": false,
                "artwork": {"480x480": "https://example.com/artwork.jpg"},
                "user": {"name": "The Tests"}
              }]
            }
            """.utf8
        )
        let api = AudiusAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                await capture.capture(request)
                return (fixture, try Self.okResponse(for: request))
            }
        )

        let response = try await api.tracks(
            query: "drum and bass",
            offset: 20,
            limit: 25
        )

        #expect(response.rawTrackCount == 1)
        #expect(response.tracks.map(\.id) == ["audius-42"])
        #expect(
            response.tracks.first?.artwork?.url480
                == "https://example.com/artwork.jpg"
        )
        #expect(response.tracks.first?.user?.name == "The Tests")

        let request = try #require(await capture.request)
        let url = try #require(request.url)
        let components = try #require(
            URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        )
        #expect(components.scheme == "https")
        #expect(components.host == "api.audius.co")
        #expect(components.path == "/v1/tracks/search")
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(.init(name: "query", value: "drum and bass")))
        #expect(queryItems.contains(.init(name: "offset", value: "20")))
        #expect(queryItems.contains(.init(name: "limit", value: "25")))
        #expect(queryItems.contains(.init(name: "api_key", value: "test-key")))
        #expect(queryItems.contains(.init(name: "app_name", value: "Crescendo")))
    }

    @Test
    func malformedRowDoesNotDiscardValidSiblingOrRawCount() async throws {
        let fixture = Data(
            """
            {
              "data": [
                {
                  "id": 42,
                  "title": "Wrong identity type",
                  "is_streamable": true,
                  "is_stream_gated": false
                },
                {
                  "id": "valid",
                  "title": "Valid",
                  "duration": 90,
                  "is_streamable": true,
                  "is_stream_gated": false,
                  "user": {"name": "Artist"}
                }
              ]
            }
            """.utf8
        )
        let api = AudiusAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                (fixture, try Self.okResponse(for: request))
            }
        )

        let response = try await api.tracks(query: "valid", offset: 0, limit: 2)

        #expect(response.rawTrackCount == 2)
        #expect(response.tracks.map(\.id) == ["valid"])
    }

    @Test
    func streamURLUsesStableTrackEndpointAndClientMetadata() throws {
        let api = AudiusAPI(
            configuration: try Self.makeConfiguration(),
            data: { _ in throw MusicProviderError.network }
        )

        let url = try api.streamURL(trackID: " track-42 ")
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        #expect(components.scheme == "https")
        #expect(components.host == "api.audius.co")
        #expect(components.path == "/v1/tracks/track-42/stream")
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(.init(name: "api_key", value: "test-key")))
        #expect(queryItems.contains(.init(name: "app_name", value: "Crescendo")))
    }

    @Test
    func nonSuccessHTTPStatusThrowsNetwork() async throws {
        let api = AudiusAPI(
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
            try await api.tracks(query: "x", offset: 0, limit: 20)
        }
    }

    @Test
    func malformedDocumentThrowsNetwork() async throws {
        let api = AudiusAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                (Data("not-json".utf8), try Self.okResponse(for: request))
            }
        )

        await #expect(throws: MusicProviderError.network) {
            try await api.tracks(query: "x", offset: 0, limit: 20)
        }
    }

    @Test
    func transportCancellationIsPreserved() async throws {
        let api = AudiusAPI(
            configuration: try Self.makeConfiguration(),
            data: { _ in throw CancellationError() }
        )

        await #expect(throws: CancellationError.self) {
            try await api.tracks(query: "x", offset: 0, limit: 20)
        }
    }
}

private extension AudiusAPITests {
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

private actor AudiusRequestCapture {
    private(set) var request: URLRequest?

    func capture(_ request: URLRequest) {
        self.request = request
    }
}
