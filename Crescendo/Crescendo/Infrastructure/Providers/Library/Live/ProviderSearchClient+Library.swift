import Foundation

extension ProviderSearchClient {
    /// Creates the read-only search adapter for the Library provider.
    ///
    /// The adapter reads one catalog snapshot, preserves catalog membership
    /// order, and resolves only the managed URLs needed for the requested page.
    /// Malformed cursors and catalog failures become
    /// `MusicProviderError.unavailable`; unresolved audio omits that membership,
    /// while unresolved artwork leaves the playable Track without artwork.
    /// It owns no Library mutation, import, recovery, caching, playback, or UI
    /// policy.
    ///
    /// - Parameters:
    ///   - libraryCatalog: Loads the confirmed Library catalog membership.
    ///   - libraryMediaStore: Resolves opaque managed-media references.
    /// - Returns: A provider-neutral paginated search client.
    static func live(
        libraryCatalog: LibraryCatalogClient,
        libraryMediaStore: LibraryMediaStoreClient
    ) -> Self {
        Self(
            searchPage: { request, limit in
                let query: String
                let offset: Int
                switch request {
                case .initial(let submittedQuery):
                    query = submittedQuery.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    offset = 0
                case .continuation(let searchCursor):
                    let cursor = try LibrarySearchCursor(
                        searchCursor: searchCursor
                    )
                    query = cursor.query
                    offset = cursor.offset
                }

                let catalogResult = await libraryCatalog.load()
                guard case let .success(catalog) = catalogResult else {
                    throw MusicProviderError.unavailable
                }

                let matchingEntries = catalog.entries.filter { entry in
                    [entry.title, entry.artistName, entry.albumTitle]
                        .compactMap { $0 }
                        .contains { field in
                            field.range(
                                of: query,
                                options: [
                                    .caseInsensitive,
                                    .diacriticInsensitive,
                                ]
                            ) != nil
                        }
                }
                let membershipOffset = max(0, offset)
                let pageEntries = Array(
                    matchingEntries
                        .dropFirst(membershipOffset)
                        .prefix(max(0, limit))
                )

                var tracks: [Track] = []
                for entry in pageEntries {
                    let playbackURLResult = await libraryMediaStore.resolveFileURL(
                        entry.audioReference
                    )
                    guard case let .success(playbackURL) = playbackURLResult else {
                        continue
                    }

                    let artworkURL: URL?
                    if let artworkReference = entry.artworkReference {
                        let artworkURLResult = await libraryMediaStore.resolveFileURL(
                            artworkReference
                        )
                        if case let .success(resolvedArtworkURL) = artworkURLResult {
                            artworkURL = resolvedArtworkURL
                        } else {
                            artworkURL = nil
                        }
                    } else {
                        artworkURL = nil
                    }

                    tracks.append(
                        Track(
                            libraryEntry: entry,
                            playbackURL: playbackURL,
                            artworkURL: artworkURL
                        )
                    )
                }

                let nextOffset = membershipOffset + pageEntries.count
                let nextCursor: SearchCursor?
                if nextOffset < matchingEntries.count {
                    nextCursor = try LibrarySearchCursor(
                        query: query,
                        offset: nextOffset
                    ).searchCursor()
                } else {
                    nextCursor = nil
                }

                return SearchPage(
                    tracks: tracks,
                    nextCursor: nextCursor
                )
            }
        )
    }
}

private extension Track {
    init(
        libraryEntry: LibraryCatalogClient.Entry,
        playbackURL: URL,
        artworkURL: URL?
    ) {
        self.init(
            id: libraryEntry.id,
            title: libraryEntry.title,
            artistName: libraryEntry.artistName,
            albumTitle: libraryEntry.albumTitle,
            artworkURL: artworkURL,
            duration: libraryEntry.duration,
            playbackURL: playbackURL
        )
    }
}
