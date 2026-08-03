import ComposableArchitecture
import SwiftUI

/// The expanded playback boundary composed from focused feature views.
///
/// This parent reads no playback state itself, so timeline observations remain
/// localized to the timeline feature view.
struct PlaybackFeatureView: View {
    let store: StoreOf<PlaybackReducer>

    var body: some View {
        VStack(spacing: 0) {
            PlaybackDismissHandleView(
                model: PlaybackDismissHandleView.Model(store)
            )

            ScrollView {
                VStack(spacing: 12) {
                    PlaybackCurrentTrackFeatureView(store: store)
                    PlaybackTimelineSectionFeatureView(store: store)
                    PlaybackControlsSectionFeatureView(store: store)
                    PlaybackUpNextSectionFeatureView(store: store)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}
