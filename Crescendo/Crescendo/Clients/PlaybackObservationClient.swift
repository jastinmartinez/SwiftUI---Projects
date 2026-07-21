import ComposableArchitecture

/// Exposes provider-confirmed playback observations.
struct PlaybackObservationClient: Sendable {
    var playbackSnapshots: @Sendable () async -> AsyncStream<PlaybackSnapshot>
}

extension DependencyValues {
    var playbackObservation: PlaybackObservationClient {
        get { self[PlaybackObservationClient.self] }
        set { self[PlaybackObservationClient.self] = newValue }
    }
}
