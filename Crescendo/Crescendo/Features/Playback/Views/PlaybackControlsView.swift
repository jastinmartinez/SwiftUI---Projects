import SwiftUI

/// Lays out the previous, primary, and next playback controls.
struct PlaybackControlsView: View {
    let model: Model

    var body: some View {
        HStack(spacing: 24) {
            PlaybackIconButtonView(model: model.previous)
            PlaybackPrimaryButtonView(model: model.primary)
            PlaybackIconButtonView(model: model.next)
        }
    }
}

extension PlaybackControlsView {
    struct Model {
        let previous: PlaybackIconButtonView.Model
        let primary: PlaybackPrimaryButtonView.Model
        let next: PlaybackIconButtonView.Model
    }
}
