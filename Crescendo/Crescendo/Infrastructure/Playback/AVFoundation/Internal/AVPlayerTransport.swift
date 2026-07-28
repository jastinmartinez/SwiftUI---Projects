@preconcurrency import AVFoundation

@MainActor
struct AVPlayerTransport {
    let player: AVPlayer

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    /// Stops transport without changing the current timeline position.
    ///
    /// The caller decides whether stopping should also seek or release the
    /// installed item.
    func stop() {
        player.pause()
    }
}
