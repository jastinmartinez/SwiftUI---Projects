import Testing

@testable import Crescendo

struct AppleMusicCatalogMappingTests {
    @Test
    func mapsProviderNeutralSongMetadata() {
        let songSummary = SongSummary(
            appleMusicNativeID: "42",
            title: "Song",
            artistName: "Artist",
            artworkURL: nil,
            duration: 215
        )
        let expectedSongID = MusicItemID(
            providerID: "apple-music",
            nativeID: "42"
        )

        #expect(songSummary.id == expectedSongID)
        #expect(songSummary.duration == 215)
    }
}
