import SwiftUI

/// Composes the primary playback row in its fixed visual order.
///
/// Child button models contain all presentation values and callbacks, leaving this
/// view responsible only for layout.
struct PlaybackControlsView: View {
    let model: Model

    var body: some View {
        HStack(spacing: 10) {
            PlaybackModeButtonView(model: model.shuffle)
            PlaybackIconButtonView(model: model.previous)
            PlaybackPrimaryButtonView(model: model.primary)
            PlaybackIconButtonView(model: model.next)
            PlaybackModeButtonView(model: model.repeatMode)
        }
    }
}

extension PlaybackControlsView {
    /// The immutable models rendered in the primary playback row.
    struct Model {
        let shuffle: PlaybackModeButtonView.Model
        let previous: PlaybackIconButtonView.Model
        let primary: PlaybackPrimaryButtonView.Model
        let next: PlaybackIconButtonView.Model
        let repeatMode: PlaybackModeButtonView.Model
    }
}

extension PlaybackControlsView.Model {
    /// Localized labels and values projected into the primary controls.
    struct Strings {
        let play: String
        let pause: String
        let previous: String
        let next: String
        let shuffle: String
        let repeatMode: String
        let modeOff: String
        let modeOn: String
        let modeAll: String
        let modeOne: String
    }
}
