import ComposableArchitecture

extension PlaybackEligibilityNoticeView.Model {
    /// Adapts search and access state into one eligibility presentation.
    @MainActor
    init(_ store: StoreOf<SearchFeature>) {
        let hasResults: Bool
        switch store.phase {
        case .loaded(let songs):
            hasResults = !songs.isEmpty
        case .idle, .loading, .failed:
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
    init(_ store: StoreOf<MusicPlaybackFeature>) {
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
