import MusicKit
import Testing

@testable import Crescendo

struct PlaybackShuffleModeAppleMusicTests {
    @Test(arguments: [
        (PlaybackShuffleMode.off, MusicPlayer.ShuffleMode.off),
        (.songs, .songs),
    ])
    func mapsShuffleModeInBothDirections(
        playbackMode: PlaybackShuffleMode,
        appleMusicMode: MusicPlayer.ShuffleMode
    ) {
        #expect(MusicPlayer.ShuffleMode(playbackMode) == appleMusicMode)
        #expect(PlaybackShuffleMode(appleMusicMode) == playbackMode)
    }
}
