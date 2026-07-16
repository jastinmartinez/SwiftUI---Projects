import Testing

@testable import Crescendo

struct AppleMusicCatalogMappingTests {
    @Test
    func namespacesSongIdentityWithAppleMusicProvider() {
        let songSummary = SongSummary(
            appleMusicNativeID: "42",
            title: "Song",
            artistName: "Artist",
            artworkURL: nil
        )
        let expectedSongID = MusicItemID(
            providerID: "apple-music",
            nativeID: "42"
        )

        #expect(songSummary.id == expectedSongID)
    }
}
