import Foundation
import MediaPlayer
import Testing

@testable import Crescendo

struct PlaybackNowPlayingProjectionMediaPlayerTests {
    @Test
    func confirmedProjectionMapsToDeterministicMediaPlayerValues() {
        let projection = makeProjection(
            status: .playing,
            position: 42,
            duration: 180
        )

        let info = projection.mediaPlayerInfo

        #expect(info[MPMediaItemPropertyTitle] as? String == "Signal")
        #expect(info[MPMediaItemPropertyArtist] as? String == "The Tests")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "Anchors")
        #expect(info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String == "jamendo:42")
        #expect(info[MPNowPlayingInfoPropertyMediaType] as? UInt == MPNowPlayingInfoMediaType.audio.rawValue)
        #expect(info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 180)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 42)
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? Int == 1)
        #expect(info[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 3)
    }

    @Test
    func absentOptionalMetadataAndDurationAreOmitted() {
        let projection = makeProjection(
            artistName: nil,
            albumTitle: nil,
            status: .paused,
            position: 12,
            duration: nil
        )

        let info = projection.mediaPlayerInfo

        #expect(info[MPMediaItemPropertyArtist] == nil)
        #expect(info[MPMediaItemPropertyAlbumTitle] == nil)
        #expect(info[MPMediaItemPropertyPlaybackDuration] == nil)
        #expect(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 12)
    }

    @Test(
        arguments: [
            PlaybackStatus.idle,
            .waiting,
            .paused,
            .stopped,
        ]
    )
    func nonPlayingStatusMapsToZeroPlaybackRate(_ status: PlaybackStatus) {
        let projection = makeProjection(status: status)

        let info = projection.mediaPlayerInfo

        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
    }

    private func makeProjection(
        artistName: String? = "The Tests",
        albumTitle: String? = "Anchors",
        status: PlaybackStatus,
        position: TimeInterval = 0,
        duration: TimeInterval? = 180
    ) -> PlaybackNowPlayingClient.Projection {
        PlaybackNowPlayingClient.Projection(
            item: .init(
                id: TrackID(providerID: .jamendo, nativeID: "42"),
                title: "Signal",
                artistName: artistName,
                albumTitle: albumTitle,
                artworkURL: nil
            ),
            transport: .init(status: status),
            timeline: .init(
                position: position,
                duration: duration
            ),
            queue: .init(index: 1, count: 3)
        )
    }
}
