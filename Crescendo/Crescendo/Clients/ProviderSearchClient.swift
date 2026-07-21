import ComposableArchitecture

/// Exposes provider-neutral catalog-search capabilities without retaining pagination state.
struct ProviderSearchClient: Sendable {
    var search:
        @Sendable (
            _ query: String,
            _ limit: Int
        ) async throws -> SearchPage
    var nextSearchPage:
        @Sendable (
            _ cursor: SearchCursor,
            _ limit: Int
        ) async throws -> SearchPage
}

extension DependencyValues {
    var providerSearch: ProviderSearchClient {
        get { self[ProviderSearchClient.self] }
        set { self[ProviderSearchClient.self] = newValue }
    }
}
