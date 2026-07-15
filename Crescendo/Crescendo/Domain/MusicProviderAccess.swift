/// Combines the independent authorization and catalog-playback eligibility dimensions.
struct MusicProviderAccess: Equatable, Sendable {
    let authorization: MusicAuthorizationState
    let playbackEligibility: CatalogPlaybackEligibility
}
