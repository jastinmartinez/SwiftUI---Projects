import ComposableArchitecture

/// Exposes provider-neutral movement through the active playback queue.
struct PlaybackNavigationClient: Sendable {
    var navigate:
        @Sendable (
            _ direction: PlaybackNavigationDirection
        ) async throws -> PlaybackNavigationResult
}

extension DependencyValues {
    var playbackNavigation: PlaybackNavigationClient {
        get { self[PlaybackNavigationClient.self] }
        set { self[PlaybackNavigationClient.self] = newValue }
    }
}
