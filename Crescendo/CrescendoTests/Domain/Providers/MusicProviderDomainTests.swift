import Testing

@testable import Crescendo

struct MusicProviderDomainTests {
    @Test
    func accessSeparatesAuthorizationFromPlaybackEligibility() {
        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .ineligible
        )

        #expect(access.authorization == .authorized)
        #expect(access.playbackEligibility == .ineligible)
    }
}
