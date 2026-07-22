import SwiftUI

/// Renders music transport actions from explicit values and callbacks.
struct PlaybackControlsView: View {
    let model: Model

    var body: some View {
        HStack(spacing: 28) {
            Button(action: model.onPrimaryAction) {
                Image(systemName: primarySymbolName)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(LinearGradient.crescendoSpectrum, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(primaryAccessibilityLabel)
            .disabled(!model.isPrimaryEnabled)

            Button(action: model.onStop) {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Locs.Playback.stop)
            .disabled(!model.isStopEnabled)
        }
    }

    private var primarySymbolName: String {
        switch model.primaryAction {
        case .play:
            "play.fill"
        case .pause:
            "pause.fill"
        }
    }

    private var primaryAccessibilityLabel: String {
        switch model.primaryAction {
        case .play:
            Locs.Playback.play
        case .pause:
            Locs.Playback.pause
        }
    }
}

extension PlaybackControlsView {
    struct Model {
        let primaryAction: PrimaryAction
        let isPrimaryEnabled: Bool
        let isStopEnabled: Bool
        let onPrimaryAction: () -> Void
        let onStop: () -> Void
    }
}

extension PlaybackControlsView.Model {
    enum PrimaryAction: Equatable {
        case play
        case pause
    }
}
