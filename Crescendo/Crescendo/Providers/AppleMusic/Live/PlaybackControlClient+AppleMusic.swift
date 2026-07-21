import ComposableArchitecture

extension PlaybackControlClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension PlaybackControlClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            playQueue: { try await provider.playQueue(itemIDs: $0, startingItemID: $1) },
            resume: { try await provider.resume() },
            pause: { await provider.pause() },
            stop: { await provider.stop() },
            seek: { await provider.seek(to: $0) }
        )
    }
}
