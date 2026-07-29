@preconcurrency import AVFoundation
import ComposableArchitecture

/// Records playback operations without invoking AVPlayer's media-loading
/// behavior.
final class PlaybackRecordingPlayer: AVPlayer {
    private let playCallCount: LockIsolated<Int>
    private let pauseCallCount: LockIsolated<Int>
    private let seekTimes: LockIsolated<[CMTime]>
    private let seekResult: Bool

    init(
        playCallCount: LockIsolated<Int>,
        pauseCallCount: LockIsolated<Int>,
        seekTimes: LockIsolated<[CMTime]>,
        seekResult: Bool = true
    ) {
        self.playCallCount = playCallCount
        self.pauseCallCount = pauseCallCount
        self.seekTimes = seekTimes
        self.seekResult = seekResult
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
        completionHandler(seekResult)
    }
}
