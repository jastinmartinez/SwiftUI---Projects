import ComposableArchitecture

extension PlaybackNavigationClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension PlaybackNavigationClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(navigate: { try await provider.navigate($0) })
    }
}
