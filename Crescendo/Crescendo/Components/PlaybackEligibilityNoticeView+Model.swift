extension PlaybackEligibilityNoticeView {
    /// The immutable presentation contract for music playback eligibility messaging.
    struct Model: Equatable {
        let presentation: Presentation
    }
}

extension PlaybackEligibilityNoticeView.Model {
    enum Presentation: Equatable {
        case hidden
        case subscriptionRequired
        case availabilityUnknown
    }
}
