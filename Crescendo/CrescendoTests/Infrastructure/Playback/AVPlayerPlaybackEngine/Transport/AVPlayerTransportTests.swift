@preconcurrency import AVFoundation
import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AVPlayerTransportTests {
    @Test
    func stopPausesSeeksToZeroAndRetainsCurrentItem() async throws {
        let playCallCount = LockIsolated(0)
        let pauseCallCount = LockIsolated(0)
        let seekTimes = LockIsolated<[CMTime]>([])
        let player = PlaybackRecordingPlayer(
            playCallCount: playCallCount,
            pauseCallCount: pauseCallCount,
            seekTimes: seekTimes
        )
        let item = AVPlayerItemFixture.make()
        player.replaceCurrentItem(with: item)
        let transport = AVPlayerTransport(
            player: player,
            timeline: AVPlayerTimeline(player: player)
        )

        let outcome = await transport.stop()

        #expect(playCallCount.value == 0)
        #expect(pauseCallCount.value == 1)
        #expect(seekTimes.value.map(\.seconds) == [0])
        #expect(player.currentItem === item)
        #expect(outcome == .completed)
    }

    @Test
    func stopReportsInterruptionWhenTheTimelineCannotReset() async {
        let player = PlaybackRecordingPlayer(
            playCallCount: LockIsolated(0),
            pauseCallCount: LockIsolated(0),
            seekTimes: LockIsolated([]),
            seekResult: false
        )
        player.replaceCurrentItem(with: AVPlayerItemFixture.make())
        let transport = AVPlayerTransport(
            player: player,
            timeline: AVPlayerTimeline(player: player)
        )

        let outcome = await transport.stop()

        #expect(outcome == .interrupted)
    }
}
