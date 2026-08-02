import ComposableArchitecture

extension ProviderSearchRailView.Model {
    /// Projects one provider reducer into its bounded rail presentation.
    ///
    /// Only the first five Tracks become cards. The reducer's full first page
    /// remains unchanged for See All and playback delegation, and no
    /// continuation callback crosses this boundary.
    @MainActor
    init(_ store: StoreOf<ProviderSearchReducer>) {
        let title: String
        switch store.providerID {
        case .library:
            title = Locs.Search.Provider.library
        case .jamendo:
            title = Locs.Search.Provider.jamendo
        default:
            title = store.providerID.rawValue
        }

        let content: Content
        switch store.status {
        case .inactive:
            content = .inactive
        case .searching:
            content = .loading
        case .loaded(let page) where page.tracks.isEmpty:
            content = .empty(
                showsLibraryAction: store.providerID == .library
            )
        case .loaded(let page):
            content = .loaded(
                page.tracks.prefix(5).map {
                    TrackRowView.Model(
                        $0,
                        accessory: .none,
                        showsDuration: false
                    )
                }
            )
        case .failed:
            content = .failed
        }

        self.init(
            id: store.providerID,
            title: title,
            content: content,
            strings: Strings(
                searching: Locs.Search.searching,
                seeAll: Locs.Search.Provider.seeAll,
                localEmptyTitle: Locs.Search.Provider.localEmptyTitle,
                localEmptyMessage: Locs.Search.Provider.localEmptyMessage,
                openLibrary: Locs.Search.Provider.openLibrary,
                failure: Locs.Search.Provider.failure,
                retry: Locs.Common.retry
            ),
            onAppear: {
                store.send(.railBecameVisible)
            },
            onRetry: {
                store.send(.retryButtonTapped)
            },
            onSeeAll: {
                store.send(.seeAllButtonTapped)
            },
            onOpenLibrary: {
                store.send(.libraryButtonTapped)
            },
            onTrackTapped: {
                store.send(.resultTapped($0))
            }
        )
    }
}
