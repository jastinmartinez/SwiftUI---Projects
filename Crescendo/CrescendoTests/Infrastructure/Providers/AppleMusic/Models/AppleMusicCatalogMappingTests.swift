import Testing

@testable import Crescendo

struct AppleMusicCatalogMappingTests {
    @Test
    func mappingPreservesProviderIdentityAndMissingAlbum() {
        let track = Track(
            appleMusicNativeID: "42",
            title: "Signal",
            artistName: "The Tests",
            albumTitle: nil,
            artworkURL: nil,
            duration: 180
        )

        #expect(track.id == TrackID(providerID: .appleMusic, nativeID: "42"))
        #expect(track.albumTitle == nil)
    }
}
