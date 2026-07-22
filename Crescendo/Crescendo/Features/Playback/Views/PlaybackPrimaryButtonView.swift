import SwiftUI

/// Renders the visually prominent play-or-pause control.
struct PlaybackPrimaryButtonView: View {
    let model: Model

    var body: some View {
        Button(action: model.perform) {
            Image(systemName: systemImage)
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

    private var systemImage: String {
        switch model.state {
        case .play:
            "play.fill"
        case .pause:
            "pause.fill"
        }
    }
}

extension PlaybackPrimaryButtonView {
    /// Contains every value required to render the primary control.
    struct Model {
        let state: State
        let accessibilityLabel: String
        let isEnabled: Bool
        let perform: () -> Void
    }
}

extension PlaybackPrimaryButtonView.Model {
    /// Identifies the action presented by the primary control.
    enum State: Equatable {
        case play
        case pause
    }
}
