import Testing

@testable import Crescendo

struct ProviderSearchClientAppleMusicTests {
    @Test
    func providerBoundClientForwardsContinuationWithoutProviderIdentity() async {
        let client = ProviderSearchClient.live(
            appleMusic: AppleMusicProvider()
        )

        await #expect(throws: DecodingError.self) {
            try await client.searchPage(
                .continuation(SearchCursor(value: "invalid")),
                10
            )
        }
    }

    // NOTE: The network-backed happy path is not covered here. AppleMusicProvider wraps
    // live MusicKit calls (MusicCatalogSearchRequest, ApplicationMusicPlayer.shared)
    // that depend on real device authorization and catalog/network access, and it
    // offers no injectable seam to fake that state. Exercising it directly in a unit
    // test would either require live MusicKit authorization or risk flaking on
    // network access, so the deterministic continuation-decoding path verifies the
    // provider-bound factory delegates without accepting provider identity.
}
