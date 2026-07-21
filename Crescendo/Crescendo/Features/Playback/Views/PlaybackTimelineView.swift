import Foundation
import SwiftUI

/// Displays duration-backed playback progress and seeking.
struct PlaybackTimelineView: View {
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
            .accessibilityLabel(model.strings.accessibilityLabel)
            .accessibilityValue(model.strings.accessibilityValue)

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

extension PlaybackTimelineView {
    struct Model {
        let position: TimeInterval
        let range: ClosedRange<TimeInterval>
        let elapsedTimeText: String
        let durationText: String
        let strings: Strings
        let onPositionChanged: (TimeInterval) -> Void
        let onDragEnded: () -> Void

        struct Strings {
            let accessibilityLabel: String
            let accessibilityValue: String
        }
    }
}

extension PlaybackTimelineView.Model {
    /// Builds the shared interactive timeline model for any player surface.
    static func make(
        duration: TimeInterval?,
        snapshot: PlaybackSnapshot,
        timeline: PlaybackTimelineFeature.State,
        supportsSeeking: Bool,
        strings: (_ elapsedTime: String, _ durationTime: String) -> Strings,
        onPositionChanged: @escaping (TimeInterval) -> Void,
        onDragEnded: @escaping () -> Void
    ) -> Self? {
        guard supportsSeeking, let duration, duration > 0 else {
            return nil
        }
        let currentPosition: TimeInterval
        switch timeline.interaction {
        case .idle:
            currentPosition = snapshot.currentTime
        case .dragging(let position), .seeking(_, let position):
            currentPosition = position
        }
        let position = min(max(currentPosition, 0), duration)
        let elapsedTimeText = position.musicDurationText
        let durationText = duration.musicDurationText
        return Self(
            position: position,
            range: 0...duration,
            elapsedTimeText: elapsedTimeText,
            durationText: durationText,
            strings: strings(elapsedTimeText, durationText),
            onPositionChanged: onPositionChanged,
            onDragEnded: onDragEnded
        )
    }
}
