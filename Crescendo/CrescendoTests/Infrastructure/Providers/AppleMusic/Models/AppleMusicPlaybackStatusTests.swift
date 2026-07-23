import Testing

@testable import Crescendo

struct AppleMusicPlaybackStatusTests {
    @Test(arguments: [
        (AppleMusicPlaybackStatus.playing, PlaybackStatus.playing),
        (.paused, .paused),
        (.stopped, .stopped),
        (.interrupted, .paused),
    ])
    func initializesPlaybackStatus(
        appleMusicStatus: AppleMusicPlaybackStatus,
        expected: PlaybackStatus
    ) {
        let playbackStatus = PlaybackStatus(appleMusicStatus)

        #expect(playbackStatus == expected)
    }
}
