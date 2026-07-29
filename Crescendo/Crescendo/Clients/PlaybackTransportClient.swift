import ComposableArchitecture

/// Exposes provider-neutral controls for the current playback item.
struct PlaybackTransportClient: Sendable {
    var play: @Sendable () async throws -> Void
    var pause: @Sendable () async throws -> Void
    /// Stops playback, resets elapsed position, and retains the current item.
    var stop: @Sendable () async -> PlaybackOperationOutcome
}

extension PlaybackTransportClient: DependencyKey {
    static let liveValue = Self(
        play: {
            fatalError("PlaybackTransportClient.play is not configured")
        },
        pause: {
            fatalError("PlaybackTransportClient.pause is not configured")
        },
        stop: {
            fatalError("PlaybackTransportClient.stop is not configured")
        }
    )
}

extension DependencyValues {
    var playbackTransport: PlaybackTransportClient {
        get { self[PlaybackTransportClient.self] }
        set { self[PlaybackTransportClient.self] = newValue }
    }
}
