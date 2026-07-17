import ComposableArchitecture

extension SearchResultsView.Model {
    /// Adapts reducer-owned search state and actions into presentation content.
    @MainActor
    init(_ store: StoreOf<SearchFeature>) {
        let content: Content =
            switch store.phase {
            case .idle:
                .idle
            case .loading:
                .loading
            case .loaded(let songs) where songs.isEmpty:
                .empty(query: store.query)
            case .loaded(let songs):
                .results(songs.map(SongRowView.Model.init))
            case .denied:
                .denied
            case .restricted:
                .restricted
            case .failed:
                .failed
            }

        self.init(
            content: content,
            onRetry: { store.send(.retryButtonTapped) },
            onOpenSettings: { store.send(.openSettingsButtonTapped) },
            onSongTapped: { store.send(.resultTapped($0)) }
        )
    }
}
