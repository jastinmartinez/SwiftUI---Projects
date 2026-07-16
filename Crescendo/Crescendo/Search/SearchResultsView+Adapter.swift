import ComposableArchitecture

extension SearchResultsView.Model {
    /// Adapts reducer-owned search state and actions into presentation content.
    @MainActor
    init(_ store: StoreOf<SearchFeature>) {
        let content: Content =
            switch store.status {
            case .idle:
                .idle
            case .loading:
                .loading
            case .loaded(let songs) where songs.isEmpty:
                .empty(query: store.query)
            case .loaded(let songs):
                .results(songs.map(SongRowView.Model.init))
            case .denied, .restricted:
                .unavailable
            case .failed:
                .failed
            }

        self.init(
            content: content,
            onRetry: { store.send(.retryButtonTapped) },
            onSongTapped: { songID in
                guard case .loaded(let songs) = store.status,
                    let song = songs.first(where: { $0.id == songID })
                else { return }
                store.send(.resultTapped(song))
            }
        )
    }
}
