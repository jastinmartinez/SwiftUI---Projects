@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct CrescendoAppCompositionTests {
    @Test
    func invalidConfigurationKeepsJamendoSelectableAndFailsClosed() async {
        let composition = CrescendoAppComposition.live(
            jamendoClientID: "  ",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in
                Issue.record("invalid configuration must not create a Jamendo API client")
                throw MusicProviderError.network
            }
        )

        #expect(composition.initialState.providerConnection.providers == [.jamendo])
        #expect(composition.initialState.search.providerID == .jamendo)
        #expect(composition.providerAccessClients[.jamendo] == nil)
        #expect(composition.providerSearchClients[.jamendo] == nil)
        #expect(composition.playbackResourceClients[.jamendo] == nil)

        let store = withDependencies {
            $0.uuid = .incrementing
        } operation: {
            composition.store()
        }
        await store.send(.providerSelected(.jamendo)).finish()

        #expect(
            store.state.providerConnection.connection
                == .restricted(providerID: .jamendo)
        )
    }

    @Test
    func validConfigurationRegistersIndependentJamendoCapabilities() async throws {
        let requests = LockIsolated<[URLRequest]>([])
        let composition = CrescendoAppComposition.live(
            jamendoClientID: "test-client",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { request in
                requests.withValue { $0.append(request) }
                let data = Data(Self.trackFixture.utf8)
                return (data, try Self.okResponse(for: request))
            }
        )

        let accessClient = try #require(
            composition.providerAccessClients[.jamendo]
        )
        let searchClient = try #require(
            composition.providerSearchClients[.jamendo]
        )
        let resourceClient = try #require(
            composition.playbackResourceClients[.jamendo]
        )

        #expect(await accessClient.currentAccess().authorization == .authorized)

        let page = try await searchClient.searchPage(
            .initial(query: "Signal"),
            20
        )
        #expect(page.tracks.map(\.id.nativeID) == ["42"])

        let trackID = TrackID(providerID: .jamendo, nativeID: "42")
        let resource = try await resourceClient.resolve(trackID)
        #expect(resource.trackID == trackID)
        #expect(
            resource.location
                == .progressive(
                    try #require(
                        URL(string: "https://example.com/audio.mp3")
                    )
                )
        )
        #expect(requests.value.count == 2)
    }

    @Test
    func successfulJamendoConnectionMakesSearchAvailable() async {
        let composition = CrescendoAppComposition.live(
            jamendoClientID: "test-client",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in throw MusicProviderError.network }
        )
        let store = TestStore(initialState: composition.initialState) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerAccessClients = composition.providerAccessClients
            $0.playbackObservation = PlaybackObservationClient(
                observations: { AsyncStream { $0.finish() } }
            )
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.providerSelected(.jamendo))
        await store.skipReceivedActions()
        await store.finish()

        #expect(
            store.state.providerConnection.connection
                == .connected(
                    providerID: .jamendo,
                    access: MusicProviderAccess(
                        authorization: .authorized,
                        playbackEligibility: .eligible
                    )
                )
        )
        #expect(
            store.state.search.providerAccess?.authorization
                == .authorized
        )
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
        let composition = CrescendoAppComposition.live(
            jamendoClientID: nil,
            player: player,
            preparer: preparer,
            data: { _ in throw MusicProviderError.network }
        )
        let trackID = TrackID(providerID: .jamendo, nativeID: "shared")
        let resource = PlaybackResource(
            trackID: trackID,
            location: .progressive(
                try #require(URL(string: "memory://shared"))
            )
        )

        #expect(player.currentItem == nil)

        try await composition.playbackItem.load(resource)
        try await composition.playbackTransport.play()
        try await composition.playbackTransport.pause()
        try await composition.playbackTimeline.seek(0)

        #expect(player.currentItem === preparedItem)
        #expect(playCallCount.value == 1)
        #expect(pauseCallCount.value == 1)
        #expect(seekTimes.value.map(\.seconds) == [0])

        var iterator =
            try await composition.playbackObservation.observations()
            .makeAsyncIterator()
        let observation = await iterator.next()
        guard case .snapshot(let snapshot) = observation else {
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

    nonisolated private static let trackFixture = """
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

    nonisolated private static func okResponse(
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
