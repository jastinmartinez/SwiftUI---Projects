extension ProviderSearchClient {
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
                let tracks = response.results.map(Track.init(jamendoTrack:))
                let nextOffset = offset + tracks.count
                let nextCursor =
                    nextOffset < response.headers.resultsFullCount
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
}
