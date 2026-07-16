import SwiftUI

/// Renders music transport actions from explicit values and callbacks.
struct MusicPlaybackControlsView: View {
    let model: Model

    var body: some View {
        HStack {
            Button(Locs.MusicPlayback.play, action: model.onPlay)
                .disabled(!model.canPlay)
            Button(Locs.MusicPlayback.pause, action: model.onPause)
            Button(Locs.MusicPlayback.stop, action: model.onStop)
        }
    }
}

extension MusicPlaybackControlsView {
    struct Model {
        let canPlay: Bool
        let onPlay: () -> Void
        let onPause: () -> Void
        let onStop: () -> Void
    }
}
