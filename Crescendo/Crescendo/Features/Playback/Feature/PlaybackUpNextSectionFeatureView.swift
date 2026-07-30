import ComposableArchitecture
import SwiftUI

/// Feature boundary for the confirmed Up Next traversal.
struct PlaybackUpNextSectionFeatureView: View {
    let store: StoreOf<PlaybackReducer>

    var body: some View {
        if let model = PlaybackUpNextView.Model(store) {
            PlaybackUpNextView(model: model)
        }
    }
}
