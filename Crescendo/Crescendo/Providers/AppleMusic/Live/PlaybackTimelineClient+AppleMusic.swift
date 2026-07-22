import ComposableArchitecture

extension PlaybackTimelineClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension PlaybackTimelineClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(seek: { await provider.seek(to: $0) })
    }
}
