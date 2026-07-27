import ComposableArchitecture

/// Exposes provider-confirmed playback observations.
@DependencyClient
struct PlaybackObservationClient: Sendable {
    var observations: @Sendable () async throws -> AsyncStream<PlaybackObservation>
}

extension PlaybackObservationClient: DependencyKey {
    static let liveValue = Self()
}

extension DependencyValues {
    var playbackObservation: PlaybackObservationClient {
        get { self[PlaybackObservationClient.self] }
        set { self[PlaybackObservationClient.self] = newValue }
    }
}
