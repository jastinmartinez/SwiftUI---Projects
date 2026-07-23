import Testing

@testable import Crescendo

struct ProviderSearchClientAppleMusicTests {
    @Test
    func searchPageThrowsNoActiveProviderWhenProviderIDDoesNotMatchAppleMusic() async throws {
        let client = ProviderSearchClient.appleMusic(AppleMusicProvider())

        await #expect(
            throws: MusicProviderError.noActiveProvider
        ) {
            try await client.searchPage(.jamendo, .initial(query: "test"), 10)
        }
    }

    // NOTE: The happy path (providerID == .appleMusic delegating through to
    // AppleMusicProvider.searchPage) is not covered here. AppleMusicProvider wraps
    // live MusicKit calls (MusicCatalogSearchRequest, ApplicationMusicPlayer.shared)
    // that depend on real device authorization and catalog/network access, and it
    // offers no injectable seam to fake that state. Exercising it directly in a unit
    // test would either require live MusicKit authorization or risk flaking/hanging
    // on network access, so it is intentionally left uncovered at this layer. The
    // guard-throws case above still fully verifies the routing guard itself, since
    // it short-circuits before any call reaches the underlying provider.
}
