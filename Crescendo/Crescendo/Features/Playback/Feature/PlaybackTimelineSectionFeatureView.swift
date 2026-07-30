import ComposableArchitecture
import SwiftUI

/// Feature boundary for timeline presentation and navigation controls.
struct PlaybackTimelineSectionFeatureView: View {
    let store: StoreOf<PlaybackReducer>

    var body: some View {
        VStack(spacing: 12) {
            if let timeline = PlaybackTimelineView.Model(store) {
                PlaybackTimelineView(model: timeline)
                PlaybackSkipControlsView(
                    model: PlaybackSkipControlsView.Model(store)
                )
            }
        }
    }
}
