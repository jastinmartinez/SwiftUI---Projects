/// Mirrors Apple Music authorization without exposing MusicKit to feature code.
enum AppleMusicAuthorizationStatus: Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

extension MusicAuthorizationStatus {
    /// Creates provider-neutral authorization from an Apple Music authorization status.
    init(_ appleMusicStatus: AppleMusicAuthorizationStatus) {
        switch appleMusicStatus {
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
    /// Creates provider-neutral eligibility from MusicKit's catalog-playback flag.
    init(canPlayCatalogContent: Bool) {
        self = canPlayCatalogContent ? .eligible : .ineligible
    }
}
