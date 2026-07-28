@preconcurrency import AVFoundation
import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AVPlayerTransportTests {
    @Test
    func stopPausesWithoutSeeking() {
        let playCallCount = LockIsolated(0)
        let pauseCallCount = LockIsolated(0)
        let seekTimes = LockIsolated<[CMTime]>([])
        let player = PlaybackRecordingPlayer(
            playCallCount: playCallCount,
            pauseCallCount: pauseCallCount,
            seekTimes: seekTimes
        )
        let transport = AVPlayerTransport(player: player)

        transport.stop()

        #expect(playCallCount.value == 0)
        #expect(pauseCallCount.value == 1)
        #expect(seekTimes.value.isEmpty)
    }
}
