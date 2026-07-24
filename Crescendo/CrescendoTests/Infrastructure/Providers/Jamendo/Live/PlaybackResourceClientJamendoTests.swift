import Foundation
import Testing

@testable import Crescendo

struct PlaybackResourceClientJamendoTests {
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

    private static func fixtureJSON(id: String, audio: String) -> String {
        """
        {
          "headers": {
            "status": "success",
            "code": 0,
            "results_count": 1,
            "results_fullcount": 1
          },
          "results": [{
            "id": "\(id)", "name": "Signal", "artist_name": "The Tests",
            "album_name": "Assertions", "image": "https://example.com/artwork.jpg",
            "duration": "180", "audio": "\(audio)"
          }]
        }
        """
    }

    @Test
    func resolvesProgressiveAudioURL() async throws {
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                let fixtureData = Data(
                    Self.fixtureJSON(id: "42", audio: "https://example.com/audio.mp3").utf8
                )
                return (fixtureData, try Self.okResponse(for: request))
            }
        )
        let client = PlaybackResourceClient.live(jamendo: api)

        let resource = try await client.resolve(TrackID(providerID: .jamendo, nativeID: "42"))
        let expectedURL = try #require(URL(string: "https://example.com/audio.mp3"))

        #expect(resource.trackID == TrackID(providerID: .jamendo, nativeID: "42"))
        #expect(resource.location == .progressive(expectedURL))
    }

    @Test
    func resourceEchoesTheRequestedTrackIDNotTheFixtureID() async throws {
        // The fixture's own "id" field deliberately differs from the requested
        // native ID, so this only passes if the resource carries the caller's
        // TrackID rather than anything derived from the Jamendo response body.
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                let fixtureData = Data(
                    Self.fixtureJSON(id: "99", audio: "https://example.com/audio.mp3").utf8
                )
                return (fixtureData, try Self.okResponse(for: request))
            }
        )
        let client = PlaybackResourceClient.live(jamendo: api)
        let requestedTrackID = TrackID(providerID: .jamendo, nativeID: "42")

        let resource = try await client.resolve(requestedTrackID)

        #expect(resource.trackID == requestedTrackID)
    }

    @Test
    func malformedAudioURLThrowsResourceUnavailable() async throws {
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                let fixtureData = Data(
                    Self.fixtureJSON(id: "42", audio: "not a url").utf8
                )
                return (fixtureData, try Self.okResponse(for: request))
            }
        )
        let client = PlaybackResourceClient.live(jamendo: api)

        await #expect(throws: PlaybackFailure.resourceUnavailable) {
            try await client.resolve(TrackID(providerID: .jamendo, nativeID: "42"))
        }
    }

    @Test
    func nonHTTPAudioSchemeThrowsResourceUnavailable() async throws {
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                let fixtureData = Data(
                    Self.fixtureJSON(id: "42", audio: "ftp://example.com/audio.mp3").utf8
                )
                return (fixtureData, try Self.okResponse(for: request))
            }
        )
        let client = PlaybackResourceClient.live(jamendo: api)

        await #expect(throws: PlaybackFailure.resourceUnavailable) {
            try await client.resolve(TrackID(providerID: .jamendo, nativeID: "42"))
        }
    }

    @Test
    func httpErrorDoesNotLeakMusicProviderErrorAcrossBoundary() async throws {
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
        let client = PlaybackResourceClient.live(jamendo: api)

        // JamendoAPI.track(id:) throws MusicProviderError.network internally;
        // this proves the resource boundary translates it to PlaybackFailure
        // rather than letting MusicProviderError escape.
        await #expect(throws: PlaybackFailure.resourceUnavailable) {
            try await client.resolve(TrackID(providerID: .jamendo, nativeID: "42"))
        }
    }

    @Test
    func emptyResultsThrowResourceUnavailable() async throws {
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
        let api = JamendoAPI(
            configuration: try Self.makeConfiguration(),
            data: { request in
                (Data(emptyResultsJSON.utf8), try Self.okResponse(for: request))
            }
        )
        let client = PlaybackResourceClient.live(jamendo: api)

        // JamendoAPI.track(id:) throws MusicProviderError.unavailable when
        // results are empty; this re-verifies the translation specifically
        // through the PlaybackResourceClient boundary.
        await #expect(throws: PlaybackFailure.resourceUnavailable) {
            try await client.resolve(TrackID(providerID: .jamendo, nativeID: "missing"))
        }
    }
}
