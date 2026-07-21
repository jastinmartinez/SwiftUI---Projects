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
    var providerSearch: ProviderSearchClient {
        get { self[ProviderSearchClient.self] }
        set { self[ProviderSearchClient.self] = newValue }
    }
}
