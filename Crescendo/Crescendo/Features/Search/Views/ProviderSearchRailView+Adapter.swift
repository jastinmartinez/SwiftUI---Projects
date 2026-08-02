import ComposableArchitecture

extension ProviderSearchRailView.Model {
    /// Projects a provider's nonempty first page into a bounded rail.
    ///
    /// Providers without results produce no rail. Only the first five Tracks
    /// become cards; the reducer retains the complete first page for See All
    /// and playback delegation, and no continuation callback crosses this
    /// boundary.
    @MainActor
    init?(_ store: StoreOf<ProviderSearchReducer>) {
        guard case .loaded(let page) = store.status,
            !page.tracks.isEmpty
        else {
            return nil
        }

        let title: String
        switch store.providerID {
        case .library:
            title = Locs.Search.Provider.library
        case .jamendo:
            title = Locs.Search.Provider.jamendo
        default:
            title = store.providerID.rawValue
        }

        self.init(
            id: store.providerID,
            title: title,
            tracks: page.tracks.prefix(5).map {
                TrackRowView.Model(
                    $0,
                    accessory: .none,
                    showsDuration: false
                )
            },
            seeAllTitle: Locs.Search.Provider.seeAll,
            onSeeAll: {
                store.send(.seeAllButtonTapped)
            },
            onTrackTapped: {
                store.send(.resultTapped($0))
            }
        )
    }
}
