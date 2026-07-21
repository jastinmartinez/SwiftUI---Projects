import ComposableArchitecture

extension PlaybackEligibilityNoticeView.Model {
    /// Adapts search and access state into one eligibility presentation.
    @MainActor
    init(_ store: StoreOf<SearchFeature>) {
        let hasResults: Bool
        switch store.status {
        case .loaded(let pagination):
            hasResults = !pagination.songs.isEmpty
        case .idle, .searching, .failed:
            hasResults = false
        }

        let presentation: Presentation =
            switch store.providerAccess?.playbackEligibility ?? .unknown {
            case .eligible:
                .hidden
            case .ineligible:
                .subscriptionRequired
            case .unknown where hasResults:
                .availabilityUnknown
            case .unknown:
                .hidden
            }

        self.init(presentation: presentation)
    }

    /// Adapts player eligibility into its presentation.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        let presentation: Presentation =
            switch store.playbackEligibility {
            case .eligible:
                .hidden
            case .ineligible:
                .subscriptionRequired
            case .unknown:
                .availabilityUnknown
            }

        self.init(presentation: presentation)
    }
}
