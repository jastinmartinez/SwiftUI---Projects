@preconcurrency import AVFoundation
import ComposableArchitecture
import Testing

@testable import Crescendo

struct AVPlayerTimelineTests {
    @Test
    @MainActor
    func seekClampsNegativeTimeToZero() async {
        let seekTimes = LockIsolated<[CMTime]>([])
        let player = SeekRecordingPlayer(seekTimes: seekTimes)
        let timeline = AVPlayerTimeline(player: player)

        let outcome = await timeline.seek(to: -10)

        #expect(seekTimes.value.map(\.seconds) == [0])
        #expect(outcome == .completed)
    }

    @Test
    @MainActor
    func seekReportsInterruptionWhenThePlayerDoesNotFinish() async {
        let player = SeekRecordingPlayer(
            seekTimes: LockIsolated([]),
            seekResult: false
        )
        let timeline = AVPlayerTimeline(player: player)

        let outcome = await timeline.seek(to: 10)

        #expect(outcome == .interrupted)
    }

    // MARK: - Helpers

    /// Captures resolved seek times without relying on AVPlayer's item-backed
    /// current-time behavior.
    private final class SeekRecordingPlayer: AVPlayer {
        private let seekTimes: LockIsolated<[CMTime]>
        private let seekResult: Bool

        init(
            seekTimes: LockIsolated<[CMTime]>,
            seekResult: Bool = true
        ) {
            self.seekTimes = seekTimes
            self.seekResult = seekResult
            super.init()
        }

        override func seek(
            to time: CMTime,
            completionHandler: @escaping (Bool) -> Void
        ) {
            seekTimes.withValue { $0.append(time) }
            completionHandler(seekResult)
        }
    }
}
