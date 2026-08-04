import Foundation

// Production constructors for provider-neutral search clients.
//
// Each provider is exposed as a documented `live(...)` overload, distinguished
// by the infrastructure dependencies required to construct it. Provider APIs,
// cursors, and mappings remain owned by their provider infrastructure; this
// extension is only the composition boundary that adapts them to
// `ProviderSearchClient`.
extension ProviderSearchClient {
    // MARK: - Audius

    /// Creates an Audius search client when the supplied bundle value is valid.
    ///
    /// Construction performs no request. Invalid configuration returns `nil` so
    /// application composition can omit only Audius while retaining other
    /// providers.
    ///
    /// - Parameters:
    ///   - audiusAPIKey: The optional generated bundle value.
    ///   - data: The shared HTTP transport operation.
    /// - Returns: A configured provider-neutral search client, or `nil` when the
    ///   bundle value is invalid.
    static func live(
        audiusAPIKey: String?,
        data:
            @escaping @Sendable (URLRequest) async throws -> (
                Data,
                URLResponse
            )
    ) -> Self? {
        let configuration = AudiusConfiguration(
            apiKey: audiusAPIKey
        )
        guard let configuration else { return nil }
        return .live(
            audius: AudiusAPI(
                configuration: configuration,
                data: data
            )
        )
    }

    /// Creates the provider-neutral search adapter backed by Audius.
    ///
    /// The adapter owns Audius continuation decoding, raw-row pagination, and
    /// provider-to-domain mapping. It does not retain search state, perform a
    /// second metadata request, or expose Audius models to Search features.
    ///
    /// - Parameter api: Audius HTTP boundary used for search and stream URLs.
    /// - Returns: A provider-neutral paginated search client.
    static func live(audius api: AudiusAPI) -> Self {
        Self(
            searchPage: { request, limit in
                let query: String
                let offset: Int
                switch request {
                case .initial(let initialQuery):
                    query = initialQuery
                    offset = 0
                case .continuation(let cursor):
                    let continuation = try AudiusSearchCursor(
                        searchCursor: cursor
                    )
                    query = continuation.query
                    offset = continuation.offset
                }

                let response = try await api.tracks(
                    query: query,
                    offset: offset,
                    limit: limit
                )
                let tracks: [Track] = response.tracks.compactMap { audiusTrack in
                    guard
                        let playbackURL = try? api.streamURL(
                            trackID: audiusTrack.id
                        )
                    else {
                        return nil
                    }
                    return Track(
                        audiusTrack: audiusTrack,
                        playbackURL: playbackURL
                    )
                }

                let nextOffset = offset + response.rawTrackCount
                let nextCursor: SearchCursor?
                if response.rawTrackCount == limit {
                    nextCursor = try AudiusSearchCursor(
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

    // MARK: - Jamendo

    /// Creates a Jamendo search client when the supplied bundle value is valid.
    ///
    /// Construction performs no request. Invalid configuration returns `nil` so
    /// application composition can omit only Jamendo while retaining other
    /// providers.
    ///
    /// - Parameters:
    ///   - jamendoClientID: The optional generated bundle value.
    ///   - data: The shared HTTP transport operation.
    /// - Returns: A configured provider-neutral search client, or `nil` when the
    ///   bundle value is invalid.
    static func live(
        jamendoClientID: String?,
        data:
            @escaping @Sendable (URLRequest) async throws -> (
                Data,
                URLResponse
            )
    ) -> Self? {
        let configuration = JamendoConfiguration(
            clientID: jamendoClientID
        )
        guard let configuration else { return nil }
        return .live(
            jamendo: JamendoAPI(
                configuration: configuration,
                data: data
            )
        )
    }

    /// Creates the provider-neutral search adapter backed by Jamendo.
    ///
    /// The adapter owns Jamendo continuation decoding, result-count pagination,
    /// and provider-to-domain mapping. It does not retain search state or expose
    /// Jamendo response models to Search features.
    ///
    /// - Parameter api: Jamendo HTTP boundary used to retrieve search results.
    /// - Returns: A provider-neutral paginated search client.
    static func live(jamendo api: JamendoAPI) -> Self {
        Self(
            searchPage: { request, limit in
                let query: String
                let offset: Int
                switch request {
                case .initial(let initialQuery):
                    query = initialQuery
                    offset = 0
                case .continuation(let cursor):
                    let continuation = try JamendoSearchCursor(
                        searchCursor: cursor
                    )
                    query = continuation.query
                    offset = continuation.offset
                }

                let response = try await api.tracks(
                    query: query,
                    offset: offset,
                    limit: limit
                )
                guard let resultsFullCount = response.headers.resultsFullCount else {
                    throw MusicProviderError.network
                }
                let tracks = response.results.compactMap(
                    Track.init(jamendoTrack:)
                )
                let nextOffset = offset + response.results.count
                let nextCursor =
                    nextOffset < resultsFullCount
                    ? try JamendoSearchCursor(
                        query: query,
                        offset: nextOffset
                    ).searchCursor()
                    : nil
                return SearchPage(
                    tracks: tracks,
                    nextCursor: nextCursor
                )
            }
        )
    }

    // MARK: - Library

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

// MARK: - Library Mapping

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
