import ComposableArchitecture

/// Fetches provider-neutral search pages without retaining pagination state.
struct ProviderSearchClient: Sendable {
    var searchPage:
        @Sendable (
            _ request: SearchPageRequest,
            _ limit: Int
        ) async throws -> SearchPage
}

extension DependencyValues {
    var providerSearchClients: ProviderClientRegistry<ProviderSearchClient> {
        get { self[ProviderSearchClientsKey.self] }
        set { self[ProviderSearchClientsKey.self] = newValue }
    }
}

private enum ProviderSearchClientsKey: DependencyKey {
    static let liveValue = ProviderClientRegistry<ProviderSearchClient>(
        clients: [:]
    )
}
