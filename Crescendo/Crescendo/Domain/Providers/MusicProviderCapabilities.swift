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
    /// Whether playback can move between items in the active queue.
    let supportsQueueTransitions: Bool
    /// The repeat behaviors the provider can apply to its active queue.
    let supportedRepeatModes: Set<PlaybackRepeatMode>
    /// Whether the provider can shuffle the active queue.
    let supportsShuffle: Bool
}

extension MusicProviderCapabilities {
    /// Enables every provider-neutral capability.
    static let allEnabled = Self(
        supportsCatalogSearch: true,
        supportsEmbeddedPlayback: true,
        supportsSeeking: true,
        supportsQueueReplacement: true,
        supportsQueueTransitions: true,
        supportedRepeatModes: [.off, .all, .one],
        supportsShuffle: true
    )
}
