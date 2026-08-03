import ComposableArchitecture
import SwiftUI

/// Feature boundary for controls, isolated from track presentation.
struct PlaybackControlsSectionFeatureView: View {
    let store: StoreOf<PlaybackReducer>

    var body: some View {
        VStack(spacing: 16) {
            PlaybackControlsView(
                model: PlaybackControlsView.Model(store)
            )
            PlaybackUtilityControlsView(
                model: PlaybackUtilityControlsView.Model(store)
            )
            PlaybackSystemOutputView()
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.horizontal, 16)
        }
    }
}
