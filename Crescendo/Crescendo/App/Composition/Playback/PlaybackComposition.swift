@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer

/// Assembles reducer-facing playback clients from one selected live engine.
///
/// This application-composition value preserves the shared-player invariant
/// and constructs system Now Playing publication. It owns no playback state,
/// reducer policy, provider routing, or application presentation.
@MainActor
struct PlaybackComposition {
    let playbackItem: PlaybackItemClient
    let playbackTransport: PlaybackTransportClient
    let playbackTimeline: PlaybackTimelineClient
    let playbackObservation: PlaybackObservationClient
    let playbackNowPlaying: PlaybackNowPlayingClient
    let playbackShuffle: PlaybackShuffleClient

    init(
        player: AVPlayer,
        preparer: AVPlayerItemPreparer,
        data:
            @escaping @Sendable (URLRequest) async throws -> (
                Data,
                URLResponse
            )
    ) {
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: preparer
        )
        let nowPlayingImage = NowPlayingImageClient.live(data: data)

        self.playbackItem = engine.item
        self.playbackTransport = engine.transport
        self.playbackTimeline = engine.timeline
        self.playbackObservation = engine.observation
        self.playbackNowPlaying = PlaybackNowPlayingClient.live(
            infoCenter: MPNowPlayingInfoCenter.default(),
            image: nowPlayingImage
        )
        self.playbackShuffle = PlaybackShuffleClient(
            shuffle: { $0.shuffled() }
        )
    }
}
