@preconcurrency import AVFoundation
import ComposableArchitecture

/// Records playback operations without invoking AVPlayer's media-loading
/// behavior.
final class PlaybackRecordingPlayer: AVPlayer {
    private let playCallCount: LockIsolated<Int>
    private let pauseCallCount: LockIsolated<Int>
    private let seekTimes: LockIsolated<[CMTime]>

    init(
        playCallCount: LockIsolated<Int>,
        pauseCallCount: LockIsolated<Int>,
        seekTimes: LockIsolated<[CMTime]>
    ) {
        self.playCallCount = playCallCount
        self.pauseCallCount = pauseCallCount
        self.seekTimes = seekTimes
        super.init()
    }

    override func play() {
        playCallCount.withValue { $0 += 1 }
    }

    override func pause() {
        pauseCallCount.withValue { $0 += 1 }
    }

    override func seek(
        to time: CMTime,
        completionHandler: @escaping (Bool) -> Void
    ) {
        seekTimes.withValue { $0.append(time) }
        completionHandler(true)
    }
}
