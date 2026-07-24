import ComposableArchitecture

extension PlaybackObservationClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension PlaybackObservationClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            observations: {
                await provider.playbackObservations()
            }
        )
    }
}
