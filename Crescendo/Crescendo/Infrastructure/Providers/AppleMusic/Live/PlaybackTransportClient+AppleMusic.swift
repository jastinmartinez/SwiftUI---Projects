import ComposableArchitecture

extension PlaybackTransportClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension PlaybackTransportClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            play: { try await provider.play() },
            pause: { await provider.pause() },
            stop: { await provider.stop() }
        )
    }
}
