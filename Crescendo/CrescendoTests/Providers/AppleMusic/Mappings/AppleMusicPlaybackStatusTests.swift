import Testing

@testable import Crescendo

struct AppleMusicPlaybackStatusTests {
    @Test(arguments: [
        (AppleMusicPlaybackStatus.playing, MusicPlaybackStatus.playing),
        (.paused, .paused),
        (.stopped, .stopped),
        (.interrupted, .paused),
    ])
    func initializesPlaybackStatus(
        appleMusicStatus: AppleMusicPlaybackStatus,
        expected: MusicPlaybackStatus
    ) {
        let playbackStatus = MusicPlaybackStatus(appleMusicStatus)

        #expect(playbackStatus == expected)
    }
}
