import ComposableArchitecture

extension ProviderAccessClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension ProviderAccessClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            currentAccess: { _ in await provider.currentAccess() },
            requestAccess: { _ in await provider.requestAccess() }
        )
    }
}
