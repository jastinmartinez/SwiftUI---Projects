import SwiftUI

/// Displays playback position and optional full-player seek actions.
struct PlaybackTimelineView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 10) {
            PlaybackSlider(model: model.slider)

            HStack {
                Text(model.elapsedTimeText)
                Spacer()
                Text(model.durationText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if !model.controls.isEmpty {
                HStack(spacing: 28) {
                    ForEach(model.controls) { control in
                        Button(action: control.perform) {
                            Image(systemName: control.systemImage)
                        }
                        .accessibilityLabel(control.accessibilityLabel)
                        .disabled(!control.isEnabled)
                    }
                }
                .font(.title3.weight(.semibold))
                .buttonStyle(.plain)
            }
        }
    }
}

extension PlaybackTimelineView {
    struct Model {
        let slider: PlaybackSlider.Model
        let elapsedTimeText: String
        let durationText: String
        let controls: [Control]
    }
}

extension PlaybackTimelineView.Model {
    struct Control: Identifiable {
        let id: ID
        let systemImage: String
        let accessibilityLabel: String
        let isEnabled: Bool
        let perform: () -> Void
    }
}

extension PlaybackTimelineView.Model.Control {
    enum ID: Hashable {
        case backward
        case restart
        case forward
    }
}
