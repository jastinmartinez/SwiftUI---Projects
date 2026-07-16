import Testing

@testable import Crescendo

struct AppleMusicPlaybackStatusTests {
    @Test(arguments: [
        (AppleMusicPlaybackStatus.playing, MusicTransportStatus.playing),
        (.paused, .paused),
        (.stopped, .stopped),
        (.interrupted, .paused),
    ])
    func initializesTransportStatus(
        appleMusicStatus: AppleMusicPlaybackStatus,
        expected: MusicTransportStatus
    ) {
        let transportStatus = MusicTransportStatus(appleMusicStatus)

        #expect(transportStatus == expected)
    }
}
