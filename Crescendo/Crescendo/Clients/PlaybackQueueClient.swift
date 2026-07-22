import ComposableArchitecture

/// Exposes provider-neutral playback-queue capabilities.
struct PlaybackQueueClient: Sendable {
    var replace:
        @Sendable (
            _ itemIDs: [MusicItemID],
            _ startingItemID: MusicItemID
        ) async throws -> Void
}

extension DependencyValues {
    var playbackQueue: PlaybackQueueClient {
        get { self[PlaybackQueueClient.self] }
        set { self[PlaybackQueueClient.self] = newValue }
    }
}
