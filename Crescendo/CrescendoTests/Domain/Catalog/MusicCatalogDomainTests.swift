import Foundation
import Testing

@testable import Crescendo

struct MusicCatalogDomainTests {
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
}
