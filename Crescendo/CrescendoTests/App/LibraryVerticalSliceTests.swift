@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

/// Proves the in-memory application path from Library load and import through
/// App delegation into the existing Playback transition.
///
/// This suite crosses feature boundaries intentionally. Client, reducer,
/// filesystem, catalog-format, and AVPlayer mechanics remain covered by their
/// focused suites; this test verifies only that their application-level facts
/// compose around the managed URL embedded in `Track`.
@MainActor
struct LibraryVerticalSliceTests {
    @Test
    func importedManagedTrackCanBecomeConfirmedPlayback() async throws {
        let sourceURL = URL(fileURLWithPath: "/external/Fixture Song.m4a")
        let stagedURL = URL(fileURLWithPath: "/managed/Staging/fixture.m4a")
        let managedURL = URL(
            fileURLWithPath: "/managed/Crescendo/Library/Audio/fixture.m4a"
        )
        let contentIdentity = Library.ContentIdentity(
            rawValue: String(repeating: "a", count: 64)
        )
        let stagedAudio = LibraryMediaStoreClient.StagedAudio(
            sourceName: sourceURL.lastPathComponent,
            temporaryURL: stagedURL,
            fileExtension: .init(rawValue: "m4a"),
            contentIdentity: contentIdentity
        )
        let metadata = AudioMetadataClient.Metadata(
            title: "Fixture Song",
            artistName: "Fixture Artist",
            albumTitle: "Fixture Album",
            albumArtistName: "Fixture Album Artist",
            duration: 180,
            trackNumber: 2,
            discNumber: 1,
            artworkData: nil
        )
        let catalogReplacements = LockIsolated(
            [LibraryCatalogClient.Snapshot]()
        )
        let loadedPlaybackURLs = LockIsolated<[URL]>([])
        let applicationSupportURL = URL.temporaryDirectory.appending(
            path: "LibraryVerticalSliceTests-\(UUID().uuidString)"
        )
        let composition = AppComposition.live(
            jamendoClientID: nil,
            audiusAPIKey: nil,
            player: AVPlayer(),
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { _ in AVPlayerItemFixture.make() }
            ),
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: applicationSupportURL
        )
        let store = Store(initialState: composition.initialState) {
            AppReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.libraryCatalog = LibraryCatalogClient(
                load: { .success(.init(entries: [])) },
                replace: { catalog in
                    catalogReplacements.withValue { $0.append(catalog) }
                    return .success(catalog)
                }
            )
            $0.libraryMediaStore = LibraryMediaStoreClient(
                stageAudio: { _ in .success(stagedAudio) },
                storeAudio: { _, trackID in
                    .success(
                        LibraryMediaStoreClient.StoredAudio(
                            trackID: trackID,
                            reference: .init(
                                rawValue: "Audio/\(trackID.nativeID).m4a"
                            ),
                            url: managedURL,
                            creationDate: Date(timeIntervalSinceReferenceDate: 1)
                        )
                    )
                },
                discardStagedAudio: { _ in },
                listStoredAudio: { .success([]) },
                identifyAudio: { _ in
                    Issue.record("Import already owns the staged content identity")
                    return .failure(.fileReadFailed)
                },
                storeArtwork: { _, _ in
                    Issue.record("Metadata contains no artwork")
                    return .failure(.fileWriteFailed)
                },
                resolveFileURL: { _ in
                    Issue.record("Playback must use the URL embedded in Track")
                    return .failure(.invalidManagedFile)
                }
            )
            $0.audioMetadata = AudioMetadataClient(
                read: { _ in .success(metadata) }
            )
            $0.playbackItem = PlaybackItemClient(
                load: { _, playbackURL, _ in
                    loadedPlaybackURLs.withValue { $0.append(playbackURL) }
                },
                commit: { _ in },
                rollback: { _ in }
            )
            $0.playbackTransport = PlaybackTransportClient(
                play: {},
                pause: {},
                stop: { .completed }
            )
            $0.playbackObservation.observations = { .finished }
        }

        await store.send(.library(.task)).finish()
        #expect(store.library.loadStatus == .loaded)

        await store.send(.library(.filesSelected([sourceURL]))).finish()
        let importedTrack = try #require(
            store.library.library.items.first?.track
        )
        #expect(importedTrack.playbackURL == managedURL)
        #expect(catalogReplacements.value.count == 1)

        await store.send(
            .library(.trackTapped(importedTrack.id))
        ).finish()
        #expect(loadedPlaybackURLs.value == [managedURL])

        let snapshot = PlaybackSnapshot(
            currentTrackID: importedTrack.id,
            status: .playing,
            position: 0,
            duration: metadata.duration,
            isSeekable: true
        )
        await store.send(
            .playback(.observationReceived(.snapshot(snapshot)))
        ).finish()

        #expect(store.playback.queue.current?.currentTrack == importedTrack)
        #expect(store.playback.session.status == .playing)
        #expect(store.playback.transition == nil)
    }
}
