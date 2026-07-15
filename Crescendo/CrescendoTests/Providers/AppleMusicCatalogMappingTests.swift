import Foundation
import Testing

@testable import Crescendo

struct AppleMusicCatalogMappingTests {
    @Test
    func initializesSongSummaryAndNamespacesIdentity() {
        let songSummary = SongSummary(
            appleMusicNativeID: "42",
            title: "Song",
            artistName: "Artist",
            artworkURL: URL(string: "https://example.com/art.jpg")
        )
        let expectedSongSummary = SongSummary(
            id: .init(
                providerID: "apple-music",
                nativeID: "42"
            ),
            title: "Song",
            artistName: "Artist",
            artworkURL: URL(string: "https://example.com/art.jpg")
        )

        #expect(songSummary == expectedSongSummary)
    }
}
