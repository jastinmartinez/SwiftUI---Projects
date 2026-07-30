import ComposableArchitecture
import SwiftUI

/// Feature boundary for current-track presentation.
///
/// This boundary observes track identity and status without reading timeline
/// position, controls, or Up Next.
struct PlaybackCurrentTrackFeatureView: View {
    let store: StoreOf<PlaybackReducer>

    var body: some View {
        PlaybackCurrentTrackView(
            model: PlaybackCurrentTrackView.Model(store)
        )
    }
}
