import ComposableArchitecture

/// Loads one resolved resource into the shared playback implementation.
@DependencyClient
struct PlaybackItemClient: Sendable {
    var load: @Sendable (_ resource: PlaybackResource) async throws -> Void
}

extension PlaybackItemClient: DependencyKey {
    static let liveValue = Self()
}

extension DependencyValues {
    var playbackItem: PlaybackItemClient {
        get { self[PlaybackItemClient.self] }
        set { self[PlaybackItemClient.self] = newValue }
    }
}
