import ComposableArchitecture

extension ProviderSearchClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension ProviderSearchClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            searchPage: { request, limit in
                try await provider.searchPage(request, limit: limit)
            }
        )
    }
}
