import AVFoundation
import AVKit
import SwiftUI

/// Bridges an explicitly injected AVPlayer into AVKit presentation.
struct VideoPlayerView: UIViewControllerRepresentable {
    private let player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        controller.player = player
    }
}
