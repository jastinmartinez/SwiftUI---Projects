import ComposableArchitecture
import SwiftUI

extension View {
    /// Places compact playback above the system-owned bottom navigation.
    ///
    /// Apply this modifier to each tab's content root. The tab view continues to
    /// own its tab bar while playback owns the optional compact presentation.
    ///
    /// - Parameter store: The playback store supplying confirmed compact-player
    ///   state and actions.
    /// - Returns: A view that conditionally inserts compact playback above its
    ///   bottom safe area.
    func playbackNowPlayingAccessory(
        store: StoreOf<PlaybackReducer>
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if let model = PlaybackNowPlayingView.Model(store) {
                PlaybackNowPlayingView(model: model)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }
}
