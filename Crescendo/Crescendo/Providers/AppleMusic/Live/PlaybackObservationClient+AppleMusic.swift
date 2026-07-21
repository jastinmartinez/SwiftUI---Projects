import ComposableArchitecture

extension PlaybackObservationClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension PlaybackObservationClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            playbackSnapshots: {
                await provider.playbackSnapshots()
            }
        )
    }
}
