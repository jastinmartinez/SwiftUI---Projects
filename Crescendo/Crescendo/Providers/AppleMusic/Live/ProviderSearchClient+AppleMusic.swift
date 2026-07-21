import ComposableArchitecture

extension ProviderSearchClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension ProviderSearchClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            search: { query, limit in
                try await provider.search(query, limit: limit)
            }
        )
    }
}
