import Testing

@testable import Crescendo

struct MusicProviderDomainTests {
    @Test
    func capabilitiesAreIndependentFlags() {
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: false,
            supportsQueueReplacement: true,
            supportsQueueTransitions: false
        )

        #expect(capabilities.supportsCatalogSearch)
        #expect(!capabilities.supportsSeeking)
        #expect(!capabilities.supportsQueueTransitions)
    }

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
