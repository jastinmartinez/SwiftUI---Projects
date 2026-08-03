import ComposableArchitecture
import SwiftUI

/// Feature boundary for timeline presentation and navigation controls.
struct PlaybackTimelineSectionFeatureView: View {
    let store: StoreOf<PlaybackReducer>

    var body: some View {
        if let timeline = PlaybackTimelineView.Model(store) {
            PlaybackTimelineView(model: timeline)
        }
    }
}
