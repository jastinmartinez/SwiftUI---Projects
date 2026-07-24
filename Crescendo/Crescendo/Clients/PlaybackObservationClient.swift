import ComposableArchitecture

/// Exposes provider-confirmed playback observations.
struct PlaybackObservationClient: Sendable {
    var observations: @Sendable () async -> AsyncStream<PlaybackObservation>
}

extension DependencyValues {
    var playbackObservation: PlaybackObservationClient {
        get { self[PlaybackObservationClient.self] }
        set { self[PlaybackObservationClient.self] = newValue }
    }
}
