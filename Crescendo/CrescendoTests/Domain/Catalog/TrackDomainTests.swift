import Foundation
import Testing

@testable import Crescendo

struct TrackDomainTests {
    @Test
    func nativeIdentityIsQualifiedByProvider() {
        let jamendo = TrackID(providerID: .jamendo, nativeID: "42")
        let localMusic = TrackID(providerID: .localMusic, nativeID: "42")

        #expect(jamendo != localMusic)
    }

    @Test
    func trackPreservesProviderNeutralMetadata() {
        let artworkURL = URL(string: "https://example.com/artwork.jpg")
        let track = Track(
            id: TrackID(providerID: .jamendo, nativeID: "42"),
            title: "Signal",
            artistName: "The Tests",
            albumTitle: "Assertions",
            artworkURL: artworkURL,
            duration: 180
        )

        #expect(track.id.providerID == .jamendo)
        #expect(track.title == "Signal")
        #expect(track.artistName == "The Tests")
        #expect(track.albumTitle == "Assertions")
        #expect(track.artworkURL == artworkURL)
        #expect(track.duration == 180)
    }
}
