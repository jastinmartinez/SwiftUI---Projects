import SwiftUI

/// Displays the primary playback action with Crescendo's emphasized styling.
///
/// The immutable model supplies the action currently offered to the user,
/// availability, accessibility text, and callback. The view owns no playback or
/// interaction state.
struct PlaybackPrimaryButtonView: View {
    let model: Model

    var body: some View {
        Button(action: model.perform) {
            Image(systemName: model.state.systemImage)
                .font(.title.bold())
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(
                    .easeInOut(duration: 0.2),
                    value: model.state
                )
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient.crescendoSpectrum,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.accessibilityLabel)
        .disabled(!model.isEnabled)
    }
}

extension PlaybackPrimaryButtonView {
    /// The immutable presentation contract for the primary playback control.
    ///
    /// `state` describes the action offered by the button rather than confirmed
    /// provider status. The presentation adapter is responsible for that projection.
    struct Model {
        let state: State
        let accessibilityLabel: String
        let isEnabled: Bool
        let perform: () -> Void
    }
}

extension PlaybackPrimaryButtonView.Model {
    /// Identifies the playback action currently offered by the primary control.
    ///
    /// Tapping `.play` requests playback; tapping `.pause` requests suspension.
    enum State: Equatable {
        case play
        case pause
    }
}

extension PlaybackPrimaryButtonView.Model.State {
    /// The SF Symbol that communicates the offered playback action.
    var systemImage: String {
        switch self {
        case .play:
            "play.fill"
        case .pause:
            "pause.fill"
        }
    }
}
