import ComposableArchitecture

extension PlaybackEligibilityNoticeView.Model {
    /// Projects search results and provider access into one eligibility presentation.
    ///
    /// Unknown eligibility is hidden before results exist and becomes visible once
    /// search has returned playable candidates.
    ///
    /// - Parameter store: The search store supplying access and result state.
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

    /// Projects expanded-player eligibility into its user-facing presentation.
    ///
    /// - Parameter store: The playback store supplying confirmed eligibility.
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
