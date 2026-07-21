import ComposableArchitecture

extension ProviderAccessClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension ProviderAccessClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            currentAccess: { await provider.currentAccess() },
            requestAccess: { await provider.requestAccess() }
        )
    }
}
