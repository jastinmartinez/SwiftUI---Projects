/// Resolves provider identity into a player-loadable resource.
struct PlaybackResourceClient: Sendable {
    var resolve: @Sendable (_ trackID: TrackID) async throws -> PlaybackResource
}
