import ComposableArchitecture

/// Produces randomized queue order without assigning policy to a media provider.
struct PlaybackShuffleClient: Sendable {
    var shuffle: @Sendable (_ trackIDs: [TrackID]) -> [TrackID]
}

extension PlaybackShuffleClient: DependencyKey {
    static let liveValue = Self(
        shuffle: { $0.shuffled() }
    )
}

extension DependencyValues {
    var playbackShuffle: PlaybackShuffleClient {
        get { self[PlaybackShuffleClient.self] }
        set { self[PlaybackShuffleClient.self] = newValue }
    }
}
