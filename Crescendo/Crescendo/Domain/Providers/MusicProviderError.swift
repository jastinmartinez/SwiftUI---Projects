/// Normalizes provider failures so features do not depend on provider-specific errors.
enum MusicProviderError: Error, Equatable, Sendable {
    case providerUnavailable(ProviderID)
    case unavailable
    case network
    case playbackFailed
}
