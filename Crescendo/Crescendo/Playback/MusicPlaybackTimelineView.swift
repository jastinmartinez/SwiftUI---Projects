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
                    set: { model.onSeek($0) }
                ),
                in: model.range
            )

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
        let onSeek: (TimeInterval) -> Void
    }
}
