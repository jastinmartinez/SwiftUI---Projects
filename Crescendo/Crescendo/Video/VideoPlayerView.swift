import AVKit
import SwiftUI

/// Bridges an explicitly injected playback session into AVKit presentation.
struct VideoPlayerView: UIViewControllerRepresentable {
    private let session: AVPlayerSession

    fileprivate init(session: AVPlayerSession) {
        self.session = session
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        session.attach(to: controller)
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        session.attach(to: controller)
    }
}

extension AVPlayerSession {
    /// Creates a player view without exposing the session's privately owned player.
    func makeVideoPlayerView() -> VideoPlayerView {
        VideoPlayerView(session: self)
    }
}
