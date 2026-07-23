import Testing

@testable import Crescendo

struct AppleMusicCatalogMappingTests {
    @Test
    func mapsProviderNeutralTrackMetadata() {
        let track = Track(
            appleMusicNativeID: "42",
            title: "Song",
            artistName: "Artist",
            albumTitle: "Album",
            artworkURL: nil,
            duration: 215
        )
        let expectedTrackID = TrackID(
            providerID: "apple-music",
            nativeID: "42"
        )

        #expect(track.id == expectedTrackID)
        #expect(track.albumTitle == "Album")
        #expect(track.duration == 215)
    }
}
