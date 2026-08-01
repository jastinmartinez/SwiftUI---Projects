@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppCompositionTests {
    @Test
    func liveStartsOnSearchWithAnEmptyIdleLibrary() {
        let composition = AppComposition.live(
            jamendoClientID: nil,
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )

        #expect(composition.initialState.selectedTab == .search)
        #expect(composition.initialState.library.library.items.isEmpty)
        #expect(composition.initialState.library.loadStatus == .idle)
    }

    @Test
    func invalidConfigurationOmitsJamendoCapabilities() {
        let composition = AppComposition.live(
            jamendoClientID: "  ",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in
                Issue.record("Invalid configuration must not create Jamendo API work")
                throw MusicProviderError.network
            },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )

        #expect(composition.initialState.search.providerID == .jamendo)
        #expect(composition.providerSearchClients[.jamendo] == nil)
    }

    @Test
    func validConfigurationRegistersPlayableJamendoSearchResults() async throws {
        let requests = LockIsolated<[URLRequest]>([])
        let composition = AppComposition.live(
            jamendoClientID: "test-client",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { request in
                requests.withValue { $0.append(request) }
                let data = Data(Self.trackFixture.utf8)
                return try (data, Self.okResponse(for: request))
            },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )

        let searchClient = try #require(
            composition.providerSearchClients[.jamendo]
        )

        let page = try await searchClient.searchPage(
            .initial(query: "Signal"),
            20
        )
        let expectedURL = try #require(
            URL(string: "https://example.com/audio.mp3")
        )
        #expect(page.tracks.map(\.id.nativeID) == ["42"])
        #expect(page.tracks.first?.playbackURL == expectedURL)
        #expect(requests.value.count == 1)
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
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )
        let trackID = TrackID(providerID: .jamendo, nativeID: "shared")
        let playbackURL = try #require(URL(string: "memory://shared"))

        #expect(player.currentItem == nil)

        try await composition.playbackItem.load(
            trackID,
            playbackURL,
            PlaybackItemInstallation(id: UUID(0))
        )
        try await composition.playbackTransport.play()
        let stopOutcome = await composition.playbackTransport.stop()

        #expect(player.currentItem === preparedItem)
        #expect(playCallCount.value == 1)
        #expect(pauseCallCount.value == 1)
        #expect(seekTimes.value.map(\.seconds) == [0])
        #expect(stopOutcome == .completed)

        var iterator =
            await composition.playbackObservation.observations()
            .makeAsyncIterator()
        let observation = await iterator.next()
        guard case .snapshot(let snapshot) = observation else {
            Issue.record("expected the supplied player's initial snapshot")
            return
        }
        #expect(snapshot.currentTrackID == trackID)
    }

    @Test
    func liveLibraryClientsShareTheInjectedManagedRoot() async throws {
        let applicationSupportURL = Self.makeApplicationSupportURL()
        let crescendoSupportURL = applicationSupportURL.appending(
            path: "Crescendo"
        )
        let libraryRootURL = crescendoSupportURL.appending(path: "Library")
        let fileSystem = ManagedLibraryFileSystem(rootURL: libraryRootURL)
        defer { try? fileSystem.removeItemIfPresent(at: libraryRootURL) }
        let composition = AppComposition.live(
            jamendoClientID: nil,
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: applicationSupportURL
        )
        let emptyCatalog = LibraryCatalogClient.Snapshot(entries: [])

        #expect(
            await composition.libraryMediaStore.listStoredAudio()
                == .success([])
        )
        #expect(
            await composition.libraryCatalog.replace(emptyCatalog)
                == .success(emptyCatalog)
        )
        #expect(
            await composition.libraryCatalog.load()
                == .success(emptyCatalog)
        )
        #expect(
            try fileSystem.readDataIfPresent(at: fileSystem.catalogURL) != nil
        )

        let metadata = try await composition.audioMetadata.read(
            Self.audioFixtureURL()
        ).get()
        #expect(metadata.title == "Fixture Song")
    }

    @Test
    func rootStoreLoadsLibraryWithRegisteredLiveDependencies() async {
        let applicationSupportURL = Self.makeApplicationSupportURL()
        let crescendoSupportURL = applicationSupportURL.appending(
            path: "Crescendo"
        )
        let libraryRootURL = crescendoSupportURL.appending(path: "Library")
        let fileSystem = ManagedLibraryFileSystem(rootURL: libraryRootURL)
        defer { try? fileSystem.removeItemIfPresent(at: libraryRootURL) }
        let composition = AppComposition.live(
            jamendoClientID: nil,
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: applicationSupportURL
        )
        let store = composition.store()

        await store.send(.library(.task)).finish()

        #expect(store.library.loadStatus == .loaded)
        #expect(store.library.library.items.isEmpty)
    }

    // MARK: - Helpers

    private static var preparer: AVPlayerItemPreparer {
        AVPlayerItemPreparer(
            loadIsPlayable: { _ in true },
            makeItem: { _ in AVPlayerItemFixture.make() }
        )
    }

    private static func makeApplicationSupportURL() -> URL {
        URL.temporaryDirectory.appending(
            path: "AppCompositionTests-\(UUID().uuidString)"
        )
    }

    private static func audioFixtureURL() throws -> URL {
        let bundle = Bundle(for: AppCompositionFixtureBundleToken.self)
        return try #require(
            bundle.url(
                forResource: "library-metadata-fixture",
                withExtension: "m4a"
            )
                ?? bundle.url(
                    forResource: "library-metadata-fixture",
                    withExtension: "m4a",
                    subdirectory: "Fixtures/Audio"
                )
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

private final class AppCompositionFixtureBundleToken: NSObject {}
