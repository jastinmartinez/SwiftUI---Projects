import Foundation
import Testing

@testable import Crescendo

struct MusicDomainTests {
    @Test
    func itemIdentityIncludesProviderIdentity() {
        let appleMusicItemID = MusicItemID(
            providerID: "apple-music",
            nativeID: "42"
        )
        let futureProviderItemID = MusicItemID(
            providerID: "future",
            nativeID: "42"
        )
        #expect(appleMusicItemID != futureProviderItemID)
    }

    @Test
    func songSummaryCarriesSharedPlaybackMetadata() {
        let song = SongSummary(
            id: MusicItemID(providerID: "apple-music", nativeID: "42"),
            title: "Example",
            artistName: "Artist",
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            duration: 215
        )
        #expect(song.artistName == "Artist")
        #expect(song.duration == 215)
    }

    @Test
    func capabilitiesAreIndependentFlags() {
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: false,
            supportsQueueReplacement: true
        )
        #expect(capabilities.supportsCatalogSearch)
        #expect(!capabilities.supportsSeeking)
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
