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
        appleMusicAuthorizationState: AppleMusicAuthorizationState,
        expected: MusicAuthorizationState
    ) {
        let authorizationState = MusicAuthorizationState(appleMusicAuthorizationState)

        #expect(authorizationState == expected)
    }

    @Test(arguments: [
        (true, CatalogPlaybackEligibility.eligible),
        (false, .ineligible),
    ])
    func initializesCatalogPlaybackEligibility(
        canPlayCatalogContent: Bool,
        expected: CatalogPlaybackEligibility
    ) {
        let playbackEligibility = CatalogPlaybackEligibility(
            canPlayCatalogContent: canPlayCatalogContent
        )

        #expect(playbackEligibility == expected)
    }
}
