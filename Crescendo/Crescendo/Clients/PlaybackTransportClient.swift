import ComposableArchitecture

/// Exposes provider-neutral controls for the current playback item.
@DependencyClient
struct PlaybackTransportClient: Sendable {
    var play: @Sendable () async throws -> Void
    var pause: @Sendable () async throws -> Void
    var stop: @Sendable () async throws -> Void
}

extension PlaybackTransportClient: DependencyKey {
    static let liveValue = Self()
}

extension DependencyValues {
    var playbackTransport: PlaybackTransportClient {
        get { self[PlaybackTransportClient.self] }
        set { self[PlaybackTransportClient.self] = newValue }
    }
}
