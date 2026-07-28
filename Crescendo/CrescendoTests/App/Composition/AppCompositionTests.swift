@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppCompositionTests {
    @Test
    func invalidConfigurationOmitsJamendoCapabilities() {
        let composition = AppComposition.live(
            jamendoClientID: "  ",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in
                Issue.record("Invalid configuration must not create Jamendo API work")
                throw MusicProviderError.network
            }
        )

        #expect(composition.initialState.search.providerID == .jamendo)
        #expect(composition.providerSearchClients[.jamendo] == nil)
        #expect(composition.playbackResourceClients[.jamendo] == nil)
    }

    @Test
    func validConfigurationRegistersIndependentJamendoCapabilities() async throws {
        let requests = LockIsolated<[URLRequest]>([])
        let composition = AppComposition.live(
            jamendoClientID: "test-client",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { request in
                requests.withValue { $0.append(request) }
                let data = Data(Self.trackFixture.utf8)
                return try (data, Self.okResponse(for: request))
            }
        )

        let searchClient = try #require(
            composition.providerSearchClients[.jamendo]
        )
        let resourceClient = try #require(
            composition.playbackResourceClients[.jamendo]
        )

        let page = try await searchClient.searchPage(
            .initial(query: "Signal"),
            20
        )
        #expect(page.tracks.map(\.id.nativeID) == ["42"])

        let trackID = TrackID(providerID: .jamendo, nativeID: "42")
        let resource = try await resourceClient.resolve(trackID)
        #expect(resource.trackID == trackID)
        #expect(
            try resource.location
                == .progressive(
                    #require(
                        URL(string: "https://example.com/audio.mp3")
                    )
                )
        )
        #expect(requests.value.count == 2)
    }

    @Test
    func livePlaybackClientsShareTheSuppliedPlayer() async throws {
        let playCallCount = LockIsolated(0)
        let pauseCallCount = LockIsolated(0)
        let seekTimes = LockIsolated<[CMTime]>([])
        let player = PlaybackRecordingPlayer(
            playCallCount: playCallCount,
            pauseCallCount: pauseCallCount,
            seekTimes: seekTimes
        )
        let preparedItem = AVPlayerItemFixture.make()
        let preparer = AVPlayerItemPreparer(
            loadIsPlayable: { _ in true },
            makeItem: { _ in preparedItem }
        )
        let composition = AppComposition.live(
            jamendoClientID: nil,
            player: player,
            preparer: preparer,
            data: { _ in throw MusicProviderError.network }
        )
        let trackID = TrackID(providerID: .jamendo, nativeID: "shared")
        let resource = try PlaybackResource(
            trackID: trackID,
            location: .progressive(
                #require(URL(string: "memory://shared"))
            )
        )

        #expect(player.currentItem == nil)

        try await composition.playbackItem.load(resource)
        try await composition.playbackTransport.play()
        try await composition.playbackTransport.stop()
        try await composition.playbackTimeline.seek(0)

        #expect(player.currentItem === preparedItem)
        #expect(playCallCount.value == 1)
        #expect(pauseCallCount.value == 1)
        #expect(seekTimes.value.map(\.seconds) == [0])

        var iterator =
            await composition.playbackObservation.observations()
                .makeAsyncIterator()
        let observation = await iterator.next()
        guard case let .snapshot(snapshot) = observation else {
            Issue.record("expected the supplied player's initial snapshot")
            return
        }
        #expect(snapshot.currentTrackID == trackID)
    }

    // MARK: - Helpers

    private static var preparer: AVPlayerItemPreparer {
        AVPlayerItemPreparer(
            loadIsPlayable: { _ in true },
            makeItem: { _ in AVPlayerItemFixture.make() }
        )
    }

    private nonisolated static let trackFixture = """
    {
      "headers": {
        "status": "success",
        "code": 0,
        "results_count": 1,
        "results_fullcount": 1
      },
      "results": [{
        "id": "42",
        "name": "Signal",
        "artist_name": "The Tests",
        "album_name": "Assertions",
        "image": "https://example.com/artwork.jpg",
        "duration": "180",
        "audio": "https://example.com/audio.mp3"
      }]
    }
    """

    private nonisolated static func okResponse(
        for request: URLRequest
    ) throws -> HTTPURLResponse {
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
