import ComposableArchitecture

extension PlaybackControlClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension PlaybackControlClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            play: { try await provider.play($0) },
            resume: { try await provider.resume() },
            pause: { await provider.pause() },
            stop: { await provider.stop() },
            seek: { await provider.seek(to: $0) }
        )
    }
}
