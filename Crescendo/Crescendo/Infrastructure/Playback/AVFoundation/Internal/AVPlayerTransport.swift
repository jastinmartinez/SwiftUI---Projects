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
}
