import AVFoundation
import Foundation

/// Controls an explicitly injected AVPlayer on the main actor.
@MainActor
final class VideoPlaybackController {
    let player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
    }

    /// Replaces the current player item without starting playback.
    func replaceCurrentItem(with item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
    }

    func pause() {
        player.pause()
    }

    func clear() {
        player.replaceCurrentItem(with: nil)
    }

    func seek(to time: TimeInterval) async {
        await player.seek(
            to: CMTime(
                seconds: max(0, time),
                preferredTimescale: 600
            )
        )
    }

    /// Publishes normalized playback snapshots while retaining AVFoundation internally.
    func playbackSnapshots() -> AsyncStream<VideoPlaybackSnapshot> {
        AsyncStream { continuation in
            let observationTask = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                while !Task.isCancelled {
                    continuation.yield(currentSnapshot())
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                observationTask.cancel()
            }
        }
    }

    /// Reads one normalized snapshot from the injected player.
    private func currentSnapshot() -> VideoPlaybackSnapshot {
        let playerTime = player.currentTime().seconds
        let currentTime = playerTime.isFinite ? max(0, playerTime) : 0
        return Self.makeSnapshot(
            hasCurrentItem: player.currentItem != nil,
            timeControlStatus: player.timeControlStatus,
            currentTime: currentTime,
            duration: player.currentItem?.duration.seconds
        )
    }

    /// Normalizes framework playback values into an app-owned snapshot.
    static func makeSnapshot(
        hasCurrentItem: Bool,
        timeControlStatus: AVPlayer.TimeControlStatus,
        currentTime: TimeInterval,
        duration: TimeInterval?
    ) -> VideoPlaybackSnapshot {
        return VideoPlaybackSnapshot(
            status: VideoPlaybackStatus(
                hasCurrentItem: hasCurrentItem,
                timeControlStatus: timeControlStatus,
                currentTime: currentTime,
                duration: duration
            ),
            currentTime: currentTime
        )
    }
}

extension VideoPlaybackStatus {
    /// Maps AVPlayer transport state without turning unknown framework cases into failures.
    fileprivate init(
        hasCurrentItem: Bool,
        timeControlStatus: AVPlayer.TimeControlStatus,
        currentTime: TimeInterval,
        duration: TimeInterval?
    ) {
        guard hasCurrentItem else {
            self = .idle
            return
        }
        let playbackDuration = duration ?? 0
        let hasDuration = playbackDuration.isFinite && playbackDuration > 0
        let reachedEnd = hasDuration && currentTime >= playbackDuration
        if reachedEnd {
            self = .ended
            return
        }

        switch timeControlStatus {
        case .waitingToPlayAtSpecifiedRate:
            self = .loading
        case .playing:
            self = .playing
        case .paused:
            self = currentTime > 0 ? .paused : .ready
        @unknown default:
            self = currentTime > 0 ? .paused : .ready
        }
    }
}
