import ComposableArchitecture

extension SearchResultsView.Model {
    /// Temporarily adapts the first provider rail into the existing search
    /// presentation while the dedicated multi-provider rail UI is introduced.
    @MainActor
    init(_ store: StoreOf<SearchReducer>) {
        guard let provider = store.providers.first else {
            self.init(
                content: .idle,
                strings: Self.strings,
                onRetry: {}
            )
            return
        }

        let providerID = provider.id
        let content: Content
        switch provider.status {
        case .inactive:
            content = .idle

        case .searching:
            content = .loading

        case .loaded(let page) where page.tracks.isEmpty:
            content = .empty(query: store.submittedQuery ?? store.query)

        case .loaded(let page):
            content = .results(
                SearchResultListView.Model(
                    summary: Locs.Search.resultsSummary(
                        count: page.tracks.count,
                        providerName: nil
                    ),
                    rows: page.tracks.map { track in
                        SearchResultListView.Model.Row(
                            id: track.id,
                            song: TrackRowView.Model(
                                track,
                                accessory: .disclosure,
                                showsDuration: false
                            ),
                            paginationTriggerID: nil
                        )
                    },
                    footer: SearchPaginationFooterView.Model(
                        content: .hidden,
                        strings: .init(
                            loading: Locs.Search.loadingMore,
                            failure: Locs.Search.loadMoreFailed,
                            retry: Locs.Common.retry
                        ),
                        onRetry: {}
                    ),
                    onTrackTapped: { trackID in
                        store.send(
                            .providers(
                                .element(
                                    id: providerID,
                                    action: .resultTapped(trackID)
                                )
                            )
                        )
                    },
                    onLoadNextPage: {}
                )
            )

        case .failed:
            content = .failed
        }

        self.init(
            content: content,
            strings: Self.strings,
            onRetry: {
                store.send(
                    .providers(
                        .element(
                            id: providerID,
                            action: .retryButtonTapped
                        )
                    )
                )
            }
        )
    }

    private static var strings: Strings {
        Strings(
            emptyTitle: Locs.Search.emptyTitle,
            searching: Locs.Search.searching,
            retry: Locs.Common.retry
        )
    }
}
