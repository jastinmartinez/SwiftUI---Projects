/// Describes a registered provider and the behavior it supports.
struct MusicProviderDescriptor: Equatable, Sendable {
    let id: MusicProviderID
    let capabilities: MusicProviderCapabilities
}

extension MusicProviderDescriptor {
    /// The Apple Music provider registered by the Phase 1 composition root.
    static let appleMusic = Self(
        id: "apple-music",
        capabilities: .init(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: true
        )
    )
}
