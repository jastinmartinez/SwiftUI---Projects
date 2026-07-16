/// Declares provider behavior without relying on provider-name checks.
struct MusicProviderCapabilities: Equatable, Sendable {
    /// Whether the provider can search its catalog.
    let supportsCatalogSearch: Bool
    /// Whether playback can occur inside Crescendo.
    let supportsEmbeddedPlayback: Bool
    /// Whether playback supports changing the current position.
    let supportsSeeking: Bool
    /// Whether playback can replace the active queue.
    let supportsQueueReplacement: Bool
}

extension MusicProviderCapabilities {
    /// Enables every provider-neutral capability.
    static let allEnabled = Self(
        supportsCatalogSearch: true,
        supportsEmbeddedPlayback: true,
        supportsSeeking: true,
        supportsQueueReplacement: true
    )
}
