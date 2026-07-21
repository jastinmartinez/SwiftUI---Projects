import ComposableArchitecture

extension SearchResultsView.Model {
    /// Adapts reducer-owned search state and actions into presentation content.
    @MainActor
    init(_ store: StoreOf<SearchFeature>, providerName: String?) {
        let content: Content
        if store.providerAccess == nil {
            content = .requiresProvider
        } else {
            content =
                switch store.status {
                case .idle:
                    .idle
                case .searching:
                    .loading
                case .loaded(let pagination) where pagination.songs.isEmpty:
                    .empty(query: store.query)
                case .loaded(let pagination):
                    .results(
                        summary: Locs.Search.resultsSummary(
                            count: pagination.songs.count,
                            providerName: providerName
                        ),
                        rows: pagination.songs.map(SongRowView.Model.init)
                    )
                case .failed:
                    .failed
                }
        }

        self.init(
            content: content,
            onRetry: { store.send(.retryButtonTapped) },
            onSongTapped: { store.send(.resultTapped($0)) }
        )
    }
}
