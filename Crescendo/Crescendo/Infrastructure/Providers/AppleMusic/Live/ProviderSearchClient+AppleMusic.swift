extension ProviderSearchClient {
    static func live(appleMusic provider: AppleMusicProvider) -> Self {
        Self(
            searchPage: { request, limit in
                return try await provider.searchPage(request, limit: limit)
            }
        )
    }
}
