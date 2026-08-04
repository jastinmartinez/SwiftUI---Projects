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
            audiusAPIKey: nil,
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
    func invalidConfigurationKeepsLibraryAsTheOnlySearchProvider() {
        let composition = AppComposition.live(
            jamendoClientID: "  ",
            audiusAPIKey: nil,
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in
                Issue.record("Invalid configuration must not create Jamendo API work")
                throw MusicProviderError.network
            },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )

        #expect(
            composition.initialState.search.providers.ids.elements
                == [.library]
        )
        #expect(composition.providerSearchClients[.library] != nil)
        #expect(composition.providerSearchClients[.jamendo] == nil)
    }

    @Test
    func blankAudiusConfigurationDoesNotRegisterAudius() {
        let composition = AppComposition.live(
            jamendoClientID: nil,
            audiusAPIKey: "   ",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in
                Issue.record("Blank configuration must not create Audius work")
                throw MusicProviderError.network
            },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )

        let providerIDs = composition.initialState.search.providers.ids.elements
        #expect(providerIDs == [.library])
        #expect(composition.providerSearchClients[.audius] == nil)
    }

    @Test
    func validRemoteConfigurationsRegisterInDeterministicOrder() {
        let composition = AppComposition.live(
            jamendoClientID: "jamendo-key",
            audiusAPIKey: "audius-key",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )

        let providerIDs = composition.initialState.search.providers.ids.elements
        #expect(providerIDs == [.library, .jamendo, .audius])
        #expect(composition.providerSearchClients[.audius] != nil)
    }

    @Test
    func validConfigurationRegistersPlayableJamendoSearchResults() async throws {
        let requests = LockIsolated<[URLRequest]>([])
        let composition = AppComposition.live(
            jamendoClientID: "test-client",
            audiusAPIKey: nil,
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

        #expect(
            composition.initialState.search.providers.ids.elements
                == [.library, .jamendo]
        )
        #expect(composition.providerSearchClients[.library] != nil)

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
    func validAudiusConfigurationRegistersPlayableSearchResults() async throws {
        let requests = LockIsolated<[URLRequest]>([])
        let composition = AppComposition.live(
            jamendoClientID: nil,
            audiusAPIKey: "audius-key",
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { request in
                requests.withValue { $0.append(request) }
                let data = Data(Self.audiusTrackFixture.utf8)
                return (data, try Self.okResponse(for: request))
            },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )
        let client = try #require(
            composition.providerSearchClients[.audius]
        )

        let page = try await client.searchPage(
            .initial(query: "Signal"),
            20
        )

        let providerIDs = composition.initialState.search.providers.ids.elements
        #expect(providerIDs == [.library, .audius])
        #expect(page.tracks.map(\.id.providerID) == [.audius])
        let playbackURL = try #require(page.tracks.first?.playbackURL)
        let components = try #require(
            URLComponents(url: playbackURL, resolvingAgainstBaseURL: false)
        )
        #expect(components.path == "/v1/tracks/audius-42/stream")
        #expect(
            components.queryItems?.contains(
                .init(name: "api_key", value: "audius-key")
            ) == true
        )
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
            audiusAPIKey: nil,
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
            audiusAPIKey: nil,
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: applicationSupportURL
        )
        let trackID = TrackID(
            providerID: .library,
            nativeID: UUID(0).uuidString
        )
        let contentIdentity = Library.ContentIdentity(
            rawValue: String(repeating: "a", count: 64)
        )
        try fileSystem.createDirectory(at: fileSystem.stagingDirectoryURL)
        let stagedURL = fileSystem.stagingDirectoryURL.appending(
            path: "fixture.mp3"
        )
        try fileSystem.writeData(Data("fixture audio".utf8), to: stagedURL)
        let storedAudio = try await composition.libraryMediaStore.storeAudio(
            LibraryMediaStoreClient.StagedAudio(
                sourceName: "fixture.mp3",
                temporaryURL: stagedURL,
                fileExtension: .init(rawValue: "mp3"),
                contentIdentity: contentIdentity
            ),
            trackID
        ).get()
        let catalog = LibraryCatalogClient.Snapshot(
            entries: [
                LibraryCatalogClient.Entry(
                    id: trackID,
                    audioReference: storedAudio.reference,
                    contentIdentity: contentIdentity,
                    title: "Shared Fixture",
                    artistName: "Composition Tests",
                    albumTitle: nil,
                    albumArtistName: nil,
                    duration: 10,
                    trackNumber: nil,
                    discNumber: nil,
                    artworkReference: nil,
                    addedAt: storedAudio.creationDate
                )
            ]
        )
        _ = try await composition.libraryCatalog.replace(catalog).get()
        let librarySearch = try #require(
            composition.providerSearchClients[.library]
        )

        let page = try await librarySearch.searchPage(
            .initial(query: "shared"),
            20
        )

        #expect(page.tracks.map(\.id.providerID) == [.library])
        #expect(page.tracks.map(\.playbackURL) == [storedAudio.url])
        #expect(
            try fileSystem.readDataIfPresent(at: fileSystem.catalogURL) != nil
        )
    }

    @Test
    func rootStoreInstallsTheComposedNowPlayingClient() async {
        let base = AppComposition.live(
            jamendoClientID: nil,
            audiusAPIKey: nil,
            player: AVPlayer(),
            preparer: Self.preparer,
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: Self.makeApplicationSupportURL()
        )
        let published = LockIsolated<[PlaybackNowPlayingClient.Projection]>([])
        let clearCount = LockIsolated(0)
        let composition = AppComposition(
            initialState: base.initialState,
            providerSearchClients: base.providerSearchClients,
            playbackItem: base.playbackItem,
            playbackTransport: base.playbackTransport,
            playbackTimeline: base.playbackTimeline,
            playbackObservation: base.playbackObservation,
            playbackNowPlaying: PlaybackNowPlayingClient(
                publish: { projection in
                    published.withValue { $0.append(projection) }
                },
                clear: {
                    clearCount.withValue { $0 += 1 }
                }
            ),
            playbackShuffle: base.playbackShuffle,
            libraryMediaStore: base.libraryMediaStore,
            audioMetadata: base.audioMetadata,
            libraryCatalog: base.libraryCatalog
        )
        let store = composition.store()

        await store.send(
            .playback(.nowPlayingPresentationRequested)
        ).finish()

        #expect(published.value.isEmpty)
        #expect(clearCount.value == 1)
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
            audiusAPIKey: nil,
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

    private nonisolated static let audiusTrackFixture = """
        {
          "data": [{
            "id": "audius-42",
            "title": "Signal",
            "duration": 180,
            "is_streamable": true,
            "is_stream_gated": false,
            "artwork": {"480x480": "https://example.com/audius.jpg"},
            "user": {"name": "The Tests"}
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
