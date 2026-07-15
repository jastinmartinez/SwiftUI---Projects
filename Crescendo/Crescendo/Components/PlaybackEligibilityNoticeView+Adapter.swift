import ComposableArchitecture

extension PlaybackEligibilityNoticeView.Model {
    /// Adapts search and access state into one eligibility presentation.
    init(_ store: StoreOf<SearchFeature>) {
        let hasResults: Bool
        switch store.status {
        case let .loaded(songs):
            hasResults = !songs.isEmpty
        case .idle, .loading, .denied, .restricted, .failed:
            hasResults = false
        }

        let presentation: Presentation = switch store.playbackEligibility {
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
}
