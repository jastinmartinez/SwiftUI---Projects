extension ProviderSearchClient {
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
}
