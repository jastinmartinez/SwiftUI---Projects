import SwiftUI

/// Presents playback progress and formatted elapsed and duration values.
///
/// Slider interaction behavior is supplied by `PlaybackSliderView.Model`; this view
/// owns only the timeline's vertical layout.
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
    /// The slider and formatted time values rendered by the timeline.
    struct Model {
        let slider: PlaybackSliderView.Model
        let elapsedTimeText: String
        let durationText: String
    }
}
