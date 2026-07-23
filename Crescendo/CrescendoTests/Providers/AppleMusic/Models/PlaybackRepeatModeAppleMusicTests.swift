import MusicKit
import Testing

@testable import Crescendo

struct PlaybackRepeatModeAppleMusicTests {
    @Test(arguments: [
        (PlaybackRepeatMode.off, MusicPlayer.RepeatMode.none),
        (.all, .all),
        (.one, .one),
    ])
    func mapsRepeatModeInBothDirections(
        playbackMode: PlaybackRepeatMode,
        appleMusicMode: MusicPlayer.RepeatMode
    ) {
        #expect(MusicPlayer.RepeatMode(playbackMode) == appleMusicMode)
        #expect(PlaybackRepeatMode(appleMusicMode) == playbackMode)
    }
}
