import Testing

@testable import Crescendo

struct AppleMusicAccessStateTests {
    @Test(arguments: [
        (AppleMusicAuthorizationState.authorized, MusicAuthorizationState.authorized),
        (.denied, .denied),
        (.restricted, .restricted),
        (.notDetermined, .notDetermined),
    ])
    func initializesAuthorizationState(
        input: AppleMusicAuthorizationState,
        expected: MusicAuthorizationState
    ) {
        #expect(MusicAuthorizationState(input) == expected)
    }

    @Test(arguments: [
        (true, CatalogPlaybackEligibility.eligible),
        (false, .ineligible),
    ])
    func initializesCatalogPlaybackEligibility(
        canPlayCatalogContent: Bool,
        expected: CatalogPlaybackEligibility
    ) {
        #expect(
            CatalogPlaybackEligibility(
                canPlayCatalogContent: canPlayCatalogContent
            ) == expected
        )
    }
}
