@preconcurrency import AVFoundation
import Foundation

@MainActor
struct AVPlayerTimeline {
    let player: AVPlayer

    /// Seeks to a nonnegative timeline position.
    ///
    /// - Parameter time: Desired position in seconds.
    /// - Returns: Whether the player finished the requested seek.
    func seek(to time: TimeInterval) async -> PlaybackOperationOutcome {
        let target = CMTime(
            seconds: max(0, time),
            preferredTimescale: 600
        )
        let didSeek = await withCheckedContinuation { continuation in
            player.seek(to: target) {
                continuation.resume(returning: $0)
            }
        }
        return didSeek ? .completed : .interrupted
    }
}
