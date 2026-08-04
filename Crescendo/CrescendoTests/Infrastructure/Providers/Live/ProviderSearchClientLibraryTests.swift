import Foundation
import IdentifiedCollections
import Testing

@testable import Crescendo

struct ProviderSearchClientLibraryTests {
    @Test
    func initialSearchTrimsQueryAndMatchesTitleArtistOrAlbum() async throws {
        let titleMatch = Self.makeEntry(
            nativeID: "title",
            title: "Café Nocturne"
        )
        let artistMatch = Self.makeEntry(
            nativeID: "artist",
            title: "Morning",
            artistName: "CAFÉ Ensemble"
        )
        let albumMatch = Self.makeEntry(
            nativeID: "album",
            title: "Evening",
            artistName: "Someone Else",
            albumTitle: "The Cafe Sessions"
        )
        let nonmatch = Self.makeEntry(
            nativeID: "nonmatch",
            title: "Silence",
            artistName: "Quiet Artist",
            albumTitle: "Stillness"
        )
        let titleURL = URL(fileURLWithPath: "/library/title.mp3")
        let artistURL = URL(fileURLWithPath: "/library/artist.mp3")
        let albumURL = URL(fileURLWithPath: "/library/album.mp3")
        let client = ProviderSearchClient.live(
            libraryCatalog: Self.catalog(
                entries: [titleMatch, artistMatch, albumMatch, nonmatch]
            ),
            libraryMediaStore: Self.mediaStore(
                resolvedURLs: [
                    titleMatch.audioReference: .success(titleURL),
                    artistMatch.audioReference: .success(artistURL),
                    albumMatch.audioReference: .success(albumURL),
                ]
            )
        )

        let page = try await client.searchPage(
            .initial(query: "  cafe  "),
            10
        )

        #expect(
            page.tracks.map(\.id.nativeID)
                == ["title", "artist", "album"]
        )
        #expect(page.nextCursor == nil)
    }

    @Test
    func pagePreservesCatalogOrderAndEmitsRemainingMembershipCursor() async throws {
        let entries = (0..<5).map {
            Self.makeEntry(
                nativeID: "\($0)",
                title: "Match \($0)"
            )
        }
        let resolvedURLs = Dictionary(
            uniqueKeysWithValues: entries.map {
                (
                    $0.audioReference,
                    Result<URL, LibraryFailure>.success(
                        URL(fileURLWithPath: "/library/\($0.id.nativeID).mp3")
                    )
                )
            }
        )
        let client = ProviderSearchClient.live(
            libraryCatalog: Self.catalog(entries: entries),
            libraryMediaStore: Self.mediaStore(resolvedURLs: resolvedURLs)
        )

        let page = try await client.searchPage(
            .initial(query: "  match "),
            2
        )

        #expect(page.tracks.map(\.id.nativeID) == ["0", "1"])
        let cursor = try #require(page.nextCursor)
        #expect(
            try LibrarySearchCursor(searchCursor: cursor)
                == LibrarySearchCursor(query: "match", offset: 2)
        )
    }

    @Test
    func continuationUsesFrozenQueryAndOffset() async throws {
        let entries = [
            Self.makeEntry(nativeID: "0", title: "Echo 0"),
            Self.makeEntry(nativeID: "1", title: "Echo 1"),
            Self.makeEntry(nativeID: "2", title: "Echo 2"),
            Self.makeEntry(nativeID: "3", title: "Echo 3"),
            Self.makeEntry(nativeID: "other", title: "Different"),
        ]
        let resolvedURLs = Dictionary(
            uniqueKeysWithValues: entries.map {
                (
                    $0.audioReference,
                    Result<URL, LibraryFailure>.success(
                        URL(fileURLWithPath: "/library/\($0.id.nativeID).mp3")
                    )
                )
            }
        )
        let client = ProviderSearchClient.live(
            libraryCatalog: Self.catalog(entries: entries),
            libraryMediaStore: Self.mediaStore(resolvedURLs: resolvedURLs)
        )
        let cursor = try LibrarySearchCursor(
            query: "echo",
            offset: 2
        ).searchCursor()

        let page = try await client.searchPage(.continuation(cursor), 2)

        #expect(page.tracks.map(\.id.nativeID) == ["2", "3"])
        #expect(page.nextCursor == nil)
    }

    @Test
    func audioResolutionCreatesPlayableTracksAndArtworkIsBestEffort() async throws {
        let complete = Self.makeEntry(
            nativeID: "complete",
            title: "Complete Song",
            artworkReference: .init(rawValue: "Artwork/complete.jpg")
        )
        let missingArtwork = Self.makeEntry(
            nativeID: "missing-artwork",
            title: "Missing Artwork Song",
            artworkReference: .init(rawValue: "Artwork/missing.jpg")
        )
        let completeAudioURL = URL(
            fileURLWithPath: "/library/complete.mp3"
        )
        let missingArtworkAudioURL = URL(
            fileURLWithPath: "/library/missing-artwork.mp3"
        )
        let completeArtworkURL = URL(
            fileURLWithPath: "/library/complete.jpg"
        )
        let client = ProviderSearchClient.live(
            libraryCatalog: Self.catalog(
                entries: [complete, missingArtwork]
            ),
            libraryMediaStore: Self.mediaStore(
                resolvedURLs: [
                    complete.audioReference: .success(completeAudioURL),
                    try #require(complete.artworkReference): .success(
                        completeArtworkURL
                    ),
                    missingArtwork.audioReference: .success(
                        missingArtworkAudioURL
                    ),
                    try #require(missingArtwork.artworkReference): .failure(
                        .invalidManagedFile
                    ),
                ]
            )
        )

        let page = try await client.searchPage(.initial(query: "song"), 10)

        #expect(
            page.tracks.map(\.playbackURL) == [
                completeAudioURL,
                missingArtworkAudioURL,
            ])
        #expect(page.tracks.map(\.artworkURL) == [completeArtworkURL, nil])
    }

    @Test
    func unresolvedAudioIsOmittedAndCursorAdvancesByMembership() async throws {
        let broken = Self.makeEntry(nativeID: "broken", title: "Match Broken")
        let playable = Self.makeEntry(
            nativeID: "playable",
            title: "Match Playable"
        )
        let later = Self.makeEntry(nativeID: "later", title: "Match Later")
        let playableURL = URL(fileURLWithPath: "/library/playable.mp3")
        let laterURL = URL(fileURLWithPath: "/library/later.mp3")
        let client = ProviderSearchClient.live(
            libraryCatalog: Self.catalog(
                entries: [broken, playable, later]
            ),
            libraryMediaStore: Self.mediaStore(
                resolvedURLs: [
                    broken.audioReference: .failure(.invalidManagedFile),
                    playable.audioReference: .success(playableURL),
                    later.audioReference: .success(laterURL),
                ]
            )
        )

        let firstPage = try await client.searchPage(
            .initial(query: "match"),
            2
        )

        #expect(firstPage.tracks.map(\.id.nativeID) == ["playable"])
        let cursor = try #require(firstPage.nextCursor)
        #expect(
            try LibrarySearchCursor(searchCursor: cursor).offset == 2
        )

        let secondPage = try await client.searchPage(
            .continuation(cursor),
            2
        )
        #expect(secondPage.tracks.map(\.id.nativeID) == ["later"])
        #expect(secondPage.nextCursor == nil)
    }

    @Test
    func catalogFailureThrowsUnavailable() async {
        let client = ProviderSearchClient.live(
            libraryCatalog: Self.catalog(result: .failure(.catalogReadFailed)),
            libraryMediaStore: Self.mediaStore()
        )

        await #expect(throws: MusicProviderError.unavailable) {
            try await client.searchPage(.initial(query: "anything"), 10)
        }
    }

    @Test
    func malformedContinuationThrowsUnavailable() async {
        let client = ProviderSearchClient.live(
            libraryCatalog: Self.catalog(entries: []),
            libraryMediaStore: Self.mediaStore()
        )

        await #expect(throws: MusicProviderError.unavailable) {
            try await client.searchPage(
                .continuation(SearchCursor(value: "not-a-cursor")),
                10
            )
        }
    }
}

private extension ProviderSearchClientLibraryTests {
    typealias CatalogLoadResult = Result<
        LibraryCatalogClient.Snapshot,
        LibraryFailure
    >
    typealias ResolvedURLResult = Result<URL, LibraryFailure>
    typealias ResolvedURLs = [LibraryMediaStoreClient.FileReference: ResolvedURLResult]

    static func makeEntry(
        nativeID: String,
        title: String,
        artistName: String? = nil,
        albumTitle: String? = nil,
        artworkReference: LibraryMediaStoreClient.FileReference? = nil
    ) -> LibraryCatalogClient.Entry {
        LibraryCatalogClient.Entry(
            id: TrackID(providerID: .library, nativeID: nativeID),
            audioReference: .init(rawValue: "Audio/\(nativeID).mp3"),
            contentIdentity: .init(rawValue: "content-\(nativeID)"),
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            albumArtistName: nil,
            duration: 180,
            trackNumber: nil,
            discNumber: nil,
            artworkReference: artworkReference,
            addedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
    }

    static func catalog(
        entries: [LibraryCatalogClient.Entry]
    ) -> LibraryCatalogClient {
        catalog(
            result: .success(
                LibraryCatalogClient.Snapshot(
                    entries: IdentifiedArray(uniqueElements: entries)
                )
            )
        )
    }

    static func catalog(
        result: CatalogLoadResult
    ) -> LibraryCatalogClient {
        LibraryCatalogClient(
            load: { result },
            replace: { _ in
                Issue.record("Library search must not replace the catalog")
                return .failure(.catalogWriteFailed)
            }
        )
    }

    static func mediaStore(
        resolvedURLs: ResolvedURLs = [:]
    ) -> LibraryMediaStoreClient {
        LibraryMediaStoreClient(
            stageAudio: { _ in
                Issue.record("Library search must not stage audio")
                return .failure(.fileReadFailed)
            },
            storeAudio: { _, _ in
                Issue.record("Library search must not store audio")
                return .failure(.fileWriteFailed)
            },
            discardStagedAudio: { _ in
                Issue.record("Library search must not discard staged audio")
            },
            listStoredAudio: {
                Issue.record("Library search must not list managed audio")
                return .failure(.fileReadFailed)
            },
            identifyAudio: { _ in
                Issue.record("Library search must not identify audio")
                return .failure(.fileReadFailed)
            },
            storeArtwork: { _, _ in
                Issue.record("Library search must not store artwork")
                return .failure(.fileWriteFailed)
            },
            resolveFileURL: { reference in
                resolvedURLs[reference] ?? .failure(.invalidManagedFile)
            }
        )
    }
}
