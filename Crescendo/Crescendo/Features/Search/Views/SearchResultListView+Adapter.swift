import ComposableArchitecture

extension SearchResultListView.Model {
    /// Projects one provider destination into vertical result presentation.
    ///
    /// The adapter exposes every accumulated Track and routes continuation,
    /// retry, and selection actions to the destination reducer. It does not
    /// derive rail previews or reach through the parent Search store.
    @MainActor
    init(_ store: StoreOf<ProviderSearchResultsReducer>) {
        let paginationTriggerID: String?
        let footerContent: SearchPaginationFooterView.Model.Content
        switch store.status {
        case .idle:
            paginationTriggerID = store.nextCursor?.value
            footerContent = .hidden
        case .loading:
            paginationTriggerID = nil
            footerContent = .loading
        case .failed:
            paginationTriggerID = nil
            footerContent = .failed
        }

        let providerName: String?
        switch store.providerID {
        case .library:
            providerName = Locs.Search.Provider.library
        case .jamendo:
            providerName = Locs.Search.Provider.jamendo
        default:
            providerName = nil
        }

        let lastTrackID = store.tracks.last?.id
        self.init(
            summary: Locs.Search.resultsSummary(
                count: store.tracks.count,
                providerName: providerName
            ),
            rows: store.tracks.map { track in
                SearchResultListView.Model.Row(
                    id: track.id,
                    song: TrackRowView.Model(
                        track,
                        accessory: .disclosure,
                        showsDuration: false
                    ),
                    paginationTriggerID: track.id == lastTrackID
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
                    store.send(.retryButtonTapped)
                }
            ),
            onTrackTapped: {
                store.send(.resultTapped($0))
            },
            onLoadNextPage: {
                store.send(.nextPageRequested)
            }
        )
    }
}
