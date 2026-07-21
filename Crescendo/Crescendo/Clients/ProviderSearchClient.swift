import ComposableArchitecture

/// Exposes provider-neutral catalog search.
struct ProviderSearchClient: Sendable {
    var search:
        @Sendable (
            _ query: String,
            _ limit: Int
        ) async throws -> [SongSummary]
}

extension DependencyValues {
    var providerSearch: ProviderSearchClient {
        get { self[ProviderSearchClient.self] }
        set { self[ProviderSearchClient.self] = newValue }
    }
}
