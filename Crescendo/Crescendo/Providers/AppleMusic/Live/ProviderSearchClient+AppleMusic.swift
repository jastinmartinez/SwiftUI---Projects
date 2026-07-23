import ComposableArchitecture

extension ProviderSearchClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension ProviderSearchClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            searchPage: { providerID, request, limit in
                guard providerID == .appleMusic else {
                    throw MusicProviderError.noActiveProvider
                }
                return try await provider.searchPage(request, limit: limit)
            }
        )
    }
}
