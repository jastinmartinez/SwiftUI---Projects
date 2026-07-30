import Foundation
import Testing

@testable import Crescendo

struct TrackJamendoAdapterTests {
    @Test
    func audioMapsToPlaybackURL() throws {
        let jamendoTrack = Self.makeJamendoTrack(
            audio: "https://example.com/audio.mp3"
        )

        let track = try #require(Track(jamendoTrack: jamendoTrack))
        let expectedURL = try #require(
            URL(string: "https://example.com/audio.mp3")
        )

        #expect(track.playbackURL == expectedURL)
    }

    @Test
    func nonHTTPAudioRejectsTheTrack() {
        let jamendoTrack = Self.makeJamendoTrack(
            audio: "ftp://example.com/audio.mp3"
        )

        #expect(Track(jamendoTrack: jamendoTrack) == nil)
    }

    @Test
    func idCombinesJamendoProviderAndNativeID() throws {
        let jamendoTrack = Self.makeJamendoTrack(id: "42")

        let track = try #require(Track(jamendoTrack: jamendoTrack))

        #expect(track.id == TrackID(providerID: .jamendo, nativeID: "42"))
    }

    @Test
    func emptyAlbumNameMapsToNilAlbumTitle() throws {
        let jamendoTrack = Self.makeJamendoTrack(albumName: "")

        let track = try #require(Track(jamendoTrack: jamendoTrack))

        #expect(track.albumTitle == nil)
    }

    @Test
    func whitespaceOnlyAlbumNameMapsToNilAlbumTitle() throws {
        let jamendoTrack = Self.makeJamendoTrack(albumName: "   \n  ")

        let track = try #require(Track(jamendoTrack: jamendoTrack))

        #expect(track.albumTitle == nil)
    }

    @Test
    func malformedArtworkMapsToNilWithoutRejectingTheRestOfTheTrack() throws {
        let jamendoTrack = Self.makeJamendoTrack(image: "ftp://example.com/art.jpg")

        let track = try #require(Track(jamendoTrack: jamendoTrack))

        #expect(track.artworkURL == nil)
        #expect(track.title == jamendoTrack.name)
        #expect(track.artistName == jamendoTrack.artistName)
        #expect(track.id == TrackID(providerID: .jamendo, nativeID: jamendoTrack.id))
        #expect(track.duration == TimeInterval(jamendoTrack.duration))
    }

    @Test
    func malformedDurationMapsToNil() throws {
        let jamendoTrack = Self.makeJamendoTrack(duration: "not-a-number")

        let track = try #require(Track(jamendoTrack: jamendoTrack))

        #expect(track.duration == nil)
    }

    // MARK: - Helpers

    private static func makeJamendoTrack(
        id: String = "42",
        name: String = "Signal",
        artistName: String = "The Tests",
        albumName: String = "Assertions",
        image: String = "https://example.com/artwork.jpg",
        duration: String = "180",
        audio: String = "https://example.com/audio.mp3"
    ) -> JamendoTrack {
        JamendoTrack(
            id: id,
            name: name,
            artistName: artistName,
            albumName: albumName,
            image: image,
            duration: duration,
            audio: audio
        )
    }
}
