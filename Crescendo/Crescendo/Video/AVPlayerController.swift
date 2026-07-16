import AVFoundation
import Foundation

/// Controls an explicitly injected AVPlayer for URL-backed media.
@MainActor
final class AVPlayerController {
    private let player: AVPlayer

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
                    continuation.yield(makeSnapshot())
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

    /// Normalizes the injected player's current values into an app-owned snapshot.
    private func makeSnapshot() -> VideoPlaybackSnapshot {
        let playerTime = player.currentTime().seconds
        let currentTime = playerTime.isFinite ? max(0, playerTime) : 0
        return VideoPlaybackSnapshot(
            status: VideoPlaybackStatus(
                hasCurrentItem: player.currentItem != nil,
                timeControlStatus: player.timeControlStatus,
                currentTime: currentTime,
                duration: player.currentItem?.duration.seconds
            ),
            currentTime: currentTime
        )
    }
}

extension VideoPlaybackStatus {
    /// Maps AVPlayer transport state without turning unknown framework cases into failures.
    init(
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
