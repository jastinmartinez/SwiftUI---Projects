/// Mirrors Apple Music authorization without exposing MusicKit to feature code.
enum AppleMusicAuthorizationState: Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

extension MusicAuthorizationState {
    /// Creates provider-neutral authorization from an Apple Music authorization state.
    init(_ appleMusicState: AppleMusicAuthorizationState) {
        switch appleMusicState {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        }
    }
}

extension CatalogPlaybackEligibility {
    /// Creates provider-neutral playback eligibility from Apple Music subscription access.
    init(canPlayCatalogContent: Bool) {
        self = canPlayCatalogContent ? .eligible : .ineligible
    }
}
