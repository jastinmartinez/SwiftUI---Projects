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
            supportsQueueTransitions: false,
            supportedRepeatModes: [.off, .one],
            supportsShuffle: false
        )

        #expect(capabilities.supportsCatalogSearch)
        #expect(!capabilities.supportsSeeking)
        #expect(!capabilities.supportsQueueTransitions)
    }

    @Test
    func capabilitiesKeepQueueModesIndependent() {
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: false,
            supportsQueueReplacement: true,
            supportsQueueTransitions: false,
            supportedRepeatModes: [.off, .one],
            supportsShuffle: false
        )

        #expect(capabilities.supportedRepeatModes == [.off, .one])
        #expect(!capabilities.supportsShuffle)
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
