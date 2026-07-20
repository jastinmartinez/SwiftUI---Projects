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

extension MusicPlaybackTimelineView.Model {
    /// Builds the shared interactive timeline model for any player surface.
    static func make(
        duration: TimeInterval?,
        snapshot: MusicPlaybackSnapshot,
        timeline: MusicPlaybackTimelineFeature.State,
        supportsSeeking: Bool,
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
        return Self(
            position: position,
            range: 0...duration,
            elapsedTimeText: position.musicDurationText,
            durationText: duration.musicDurationText,
            onPositionChanged: onPositionChanged,
            onDragEnded: onDragEnded
        )
    }
}
