import ComposableArchitecture

extension SearchResultsView.Model {
    /// Adapts reducer-owned search state and actions into presentation content.
    @MainActor
    init(_ store: StoreOf<SearchFeature>, providerName: String?) {
        let content: Content
        if store.providerAccess == nil {
            content = .requiresProvider
        } else {
            switch store.status {
            case .idle:
                content = .idle

            case .searching:
                content = .loading

            case .loaded(let pagination) where pagination.songs.isEmpty:
                content = .empty(query: store.query)

            case .loaded(let pagination):
                let footerContent: SearchPaginationFooterView.Model.Content
                switch pagination.status {
                case .idle:
                    footerContent =
                        pagination.nextCursor.map {
                            .ready(triggerID: $0.value)
                        } ?? .hidden
                case .loading:
                    footerContent = .loading
                case .failed:
                    footerContent = .failed
                }

                content = .results(
                    summary: Locs.Search.resultsSummary(
                        count: pagination.songs.count,
                        providerName: providerName
                    ),
                    rows: pagination.songs.map(SongRowView.Model.init),
                    footer: SearchPaginationFooterView.Model(
                        content: footerContent,
                        strings: .init(
                            loading: Locs.Search.loadingMore,
                            failure: Locs.Search.loadMoreFailed,
                            retry: Locs.Common.retry
                        ),
                        onLoadNextPage: {
                            store.send(.pagination(.nextPageRequested))
                        },
                        onRetry: {
                            store.send(.pagination(.retryButtonTapped))
                        }
                    )
                )

            case .failed:
                content = .failed
            }
        }

        self.init(
            content: content,
            onRetry: { store.send(.retryButtonTapped) },
            onSongTapped: { store.send(.resultTapped($0)) }
        )
    }
}
