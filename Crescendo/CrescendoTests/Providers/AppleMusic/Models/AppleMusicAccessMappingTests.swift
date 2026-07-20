import Testing

@testable import Crescendo

struct AppleMusicAccessMappingTests {
    @Test(arguments: [
        (AppleMusicAuthorizationStatus.authorized, MusicAuthorizationStatus.authorized),
        (.denied, .denied),
        (.restricted, .restricted),
        (.notDetermined, .notDetermined),
    ])
    func initializesAuthorizationStatus(
        appleMusicAuthorizationStatus: AppleMusicAuthorizationStatus,
        expected: MusicAuthorizationStatus
    ) {
        let authorizationStatus = MusicAuthorizationStatus(appleMusicAuthorizationStatus)

        #expect(authorizationStatus == expected)
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
