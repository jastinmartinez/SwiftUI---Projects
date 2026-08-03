import MediaPlayer
import SwiftUI

/// Presents the operating system's output-volume and route controls.
///
/// MediaPlayer owns the displayed volume, available routes, interactions,
/// and accessibility behavior. This boundary does not copy system output
/// state into Crescendo or send playback actions.
struct PlaybackSystemOutputView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        MPVolumeView(frame: .zero)
    }

    func updateUIView(
        _ volumeView: MPVolumeView,
        context: Context
    ) {}
}
