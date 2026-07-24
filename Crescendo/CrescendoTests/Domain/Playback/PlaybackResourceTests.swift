import Foundation
import Testing

@testable import Crescendo

struct PlaybackResourceTests {
    @Test
    func resourceOwnsTheIdentityItWillInstall() {
        let trackID = TrackID(providerID: .jamendo, nativeID: "42")
        let url = URL(string: "https://example.com/audio.mp3")
        let resource = url.map {
            PlaybackResource(
                trackID: trackID,
                location: .progressive($0)
            )
        }

        #expect(resource?.trackID == trackID)
        #expect(resource?.location == url.map(PlaybackResource.Location.progressive))
    }

    @Test
    func locationsRemainSemanticallyDistinct() {
        let url = URL(fileURLWithPath: "/tmp/track.caf")

        #expect(PlaybackResource.Location.localFile(url) != .hls(url))
        #expect(PlaybackResource.Location.progressive(url) != .hls(url))
    }
}
