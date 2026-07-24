@preconcurrency import AVFoundation
import Testing

@testable import Crescendo

struct AVPlayerTimelineTests {
    /// Captures the `CMTime` a seek resolves to without installing any media,
    /// since an item-less `AVPlayer` never reports a meaningful
    /// `currentTime()` after seeking.
    private final class SeekRecordingPlayer: AVPlayer {
        private(set) var lastSeekTime: CMTime?

        override func seek(
            to time: CMTime,
            completionHandler: @escaping (Bool) -> Void
        ) {
            lastSeekTime = time
            completionHandler(true)
        }
    }

    @Test
    @MainActor
    func seekClampsNegativeTimeToZero() async {
        let player = SeekRecordingPlayer()
        let timeline = AVPlayerTimeline(player: player)

        await timeline.seek(to: -10)

        #expect(player.lastSeekTime?.seconds == 0)
    }
}
