import ComposableArchitecture

extension PlaybackEligibilityNoticeView.Model {
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

        self.init(presentation: presentation, strings: .localized)
    }
}

extension PlaybackEligibilityNoticeView.Model.Strings {
    /// Production localization wiring for playback eligibility.
    static let localized = Self(
        subscriptionRequired: Locs.MusicAccess.subscriptionRequired,
        availabilityUnknown: Locs.MusicAccess.availabilityUnknown
    )
}
