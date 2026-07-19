import Foundation
import SwiftUI

/// Displays duration-backed playback progress and seeking.
struct MusicPlaybackTimelineView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { model.position },
                    set: { model.onPositionChanged($0) }
                ),
                in: model.range,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    model.onDragEnded()
                }
            )
            .accessibilityLabel(model.accessibilityLabel)
            .accessibilityValue(model.accessibilityValue)

            HStack {
                Text(model.elapsedTimeText)
                Spacer()
                Text(model.durationText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

extension MusicPlaybackTimelineView {
    struct Model {
        let position: TimeInterval
        let range: ClosedRange<TimeInterval>
        let elapsedTimeText: String
        let durationText: String
        let onPositionChanged: (TimeInterval) -> Void
        let onDragEnded: () -> Void

        var accessibilityLabel: String {
            Locs.MusicPlayback.position
        }

        var accessibilityValue: String {
            Locs.MusicPlayback.positionValue(
                elapsedTime: elapsedTimeText,
                durationTime: durationText
            )
        }
    }
}
