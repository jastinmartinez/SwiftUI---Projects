import Foundation
import Testing

@testable import Crescendo

struct TrackAudiusAdapterTests {
    @Test
    func eligibleTrackMapsIntoProviderNeutralTrack() throws {
        let playbackURL = try #require(
            URL(string: "https://api.audius.co/v1/tracks/42/stream")
        )
        let track = try #require(
            Track(
                audiusTrack: Self.makeTrack(),
                playbackURL: playbackURL
            )
        )

        #expect(track.id == TrackID(providerID: .audius, nativeID: "42"))
        #expect(track.title == "Signal")
        #expect(track.artistName == "The Tests")
        #expect(track.albumTitle == nil)
        #expect(track.artworkURL == URL(string: "https://example.com/480.jpg"))
        #expect(track.duration == 180)
        #expect(track.playbackURL == playbackURL)
    }

    @Test
    func ineligibleTrackIsRejected() throws {
        let playbackURL = try #require(
            URL(string: "https://api.audius.co/v1/tracks/42/stream")
        )

        #expect(
            Track(
                audiusTrack: Self.makeTrack(isStreamable: false),
                playbackURL: playbackURL
            ) == nil
        )
        #expect(
            Track(
                audiusTrack: Self.makeTrack(isStreamGated: true),
                playbackURL: playbackURL
            ) == nil
        )
        #expect(
            Track(
                audiusTrack: Self.makeTrack(id: "   "),
                playbackURL: playbackURL
            ) == nil
        )
    }

    @Test
    func nonHTTPSPlaybackURLIsRejected() throws {
        let playbackURL = try #require(
            URL(string: "http://api.audius.co/v1/tracks/42/stream")
        )

        #expect(
            Track(
                audiusTrack: Self.makeTrack(),
                playbackURL: playbackURL
            ) == nil
        )
    }

    @Test
    func malformedOptionalMetadataDoesNotRejectPlayableTrack() throws {
        let playbackURL = try #require(
            URL(string: "https://api.audius.co/v1/tracks/42/stream")
        )
        let track = try #require(
            Track(
                audiusTrack: Self.makeTrack(
                    artworkURL: "ftp://example.com/art.jpg",
                    artistName: "   "
                ),
                playbackURL: playbackURL
            )
        )

        #expect(track.artworkURL == nil)
        #expect(track.artistName == nil)
    }

    private static func makeTrack(
        id: String = "42",
        isStreamable: Bool = true,
        isStreamGated: Bool = false,
        artworkURL: String? = "https://example.com/480.jpg",
        artistName: String? = "The Tests"
    ) -> AudiusTrack {
        AudiusTrack(
            id: id,
            title: "Signal",
            duration: 180,
            isStreamable: isStreamable,
            isStreamGated: isStreamGated,
            artwork: .init(url480: artworkURL),
            user: .init(name: artistName)
        )
    }
}
