import ComposableArchitecture

/// Resolves provider identity into a player-loadable resource.
struct PlaybackResourceClient: Sendable {
    var resolve: @Sendable (_ trackID: TrackID) async throws -> PlaybackResource
}

private enum PlaybackResourceClientsKey: DependencyKey {
    static let liveValue = ProviderClientRegistry<PlaybackResourceClient>(
        clients: [:]
    )
}

extension DependencyValues {
    var playbackResourceClients: ProviderClientRegistry<PlaybackResourceClient> {
        get { self[PlaybackResourceClientsKey.self] }
        set { self[PlaybackResourceClientsKey.self] = newValue }
    }
}
