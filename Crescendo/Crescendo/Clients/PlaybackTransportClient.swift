import ComposableArchitecture

/// Exposes provider-neutral controls for the current playback item.
struct PlaybackTransportClient: Sendable {
    var play: @Sendable () async throws -> Void
    var pause: @Sendable () async throws -> Void
    var stop: @Sendable () async throws -> Void
}

extension DependencyValues {
    var playbackTransport: PlaybackTransportClient {
        get { self[PlaybackTransportClient.self] }
        set { self[PlaybackTransportClient.self] = newValue }
    }
}
