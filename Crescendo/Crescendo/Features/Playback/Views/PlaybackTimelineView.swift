import SwiftUI

/// Displays playback position without owning adjacent command rows.
struct PlaybackTimelineView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 10) {
            PlaybackSliderView(model: model.slider)

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
        let slider: PlaybackSliderView.Model
        let elapsedTimeText: String
        let durationText: String
    }
}
