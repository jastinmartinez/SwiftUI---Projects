@preconcurrency import AVFoundation
import Foundation

@MainActor
struct AVPlayerTimeline {
    let player: AVPlayer

    /// Seeks to a nonnegative timeline position.
    ///
    /// - Parameter time: Desired position in seconds.
    func seek(to time: TimeInterval) async {
        let target = CMTime(
            seconds: max(0, time),
            preferredTimescale: 600
        )
        await player.seek(to: target)
    }
}
