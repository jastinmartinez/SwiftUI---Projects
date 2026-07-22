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
                let paginationTriggerID: String?
                let footerContent: SearchPaginationFooterView.Model.Content
                switch pagination.status {
                case .idle:
                    paginationTriggerID = pagination.nextCursor?.value
                    footerContent = .hidden
                case .loading:
                    paginationTriggerID = nil
                    footerContent = .loading
                case .failed:
                    paginationTriggerID = nil
                    footerContent = .failed
                }
                let lastSongID = pagination.songs.last?.id

                content = .results(
                    SearchResultListView.Model(
                        summary: Locs.Search.resultsSummary(
                            count: pagination.songs.count,
                            providerName: providerName
                        ),
                        rows: pagination.songs.map { song in
                            SearchResultListView.Model.Row(
                                id: song.id,
                                song: SongRowView.Model(song),
                                paginationTriggerID: song.id == lastSongID
                                    ? paginationTriggerID
                                    : nil
                            )
                        },
                        footer: SearchPaginationFooterView.Model(
                            content: footerContent,
                            strings: .init(
                                loading: Locs.Search.loadingMore,
                                failure: Locs.Search.loadMoreFailed,
                                retry: Locs.Common.retry
                            ),
                            onRetry: {
                                store.send(.pagination(.retryButtonTapped))
                            }
                        ),
                        onSongTapped: { store.send(.resultTapped($0)) },
                        onLoadNextPage: {
                            store.send(.pagination(.nextPageRequested))
                        }
                    )
                )

            case .failed:
                content = .failed
            }
        }

        self.init(
            content: content,
            onRetry: { store.send(.retryButtonTapped) }
        )
    }
}
