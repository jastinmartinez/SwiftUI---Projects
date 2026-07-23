import ComposableArchitecture

/// Exposes provider-neutral control of the active playback queue.
struct PlaybackQueueClient: Sendable {
    var replace:
        @Sendable (
            _ itemIDs: [MusicItemID],
            _ startingItemID: MusicItemID
        ) async throws -> Void
    var navigate:
        @Sendable (
            _ direction: PlaybackQueueNavigationDirection
        ) async throws -> PlaybackQueueNavigationResult
    var setRepeat: @Sendable (_ mode: PlaybackRepeatMode) async throws -> Void
    var setShuffle: @Sendable (_ mode: PlaybackShuffleMode) async throws -> Void
}

extension DependencyValues {
    var playbackQueue: PlaybackQueueClient {
        get { self[PlaybackQueueClient.self] }
        set { self[PlaybackQueueClient.self] = newValue }
    }
}
