@preconcurrency import AVFoundation

@MainActor
struct AVPlayerTransport {
    let player: AVPlayer
    let timeline: AVPlayerTimeline

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    /// Stops playback, resets elapsed position, and retains the current item.
    func stop() async -> PlaybackOperationOutcome {
        player.pause()
        switch await timeline.seek(to: 0) {
        case .completed:
            return .completed
        case .interrupted:
            return .interrupted
        }
    }
}
