/// Combines the independent authorization and catalog-playback eligibility dimensions.
struct MusicProviderAccess: Equatable, Sendable {
    let authorization: MusicAuthorizationStatus
    let playbackEligibility: CatalogPlaybackEligibility
}
