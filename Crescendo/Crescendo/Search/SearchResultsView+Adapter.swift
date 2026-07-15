import ComposableArchitecture

extension SearchResultsView.Model {
    /// Adapts reducer-owned search state and actions into presentation content.
    init(_ store: StoreOf<SearchFeature>) {
        let content: Content = switch store.status {
        case .idle:
            .idle
        case .loading:
            .loading
        case let .loaded(songs) where songs.isEmpty:
            .empty(query: store.query)
        case let .loaded(songs):
            .results(songs.map(SongRowView.Model.init))
        case .denied, .restricted:
            .unavailable
        case .failed:
            .failed
        }

        self.init(
            content: content,
            onRetry: { store.send(.retryButtonTapped) }
        )
    }
}
