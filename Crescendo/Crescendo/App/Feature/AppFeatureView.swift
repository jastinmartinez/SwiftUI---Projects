import ComposableArchitecture
import SwiftUI

/// The application feature boundary that owns Crescendo's root store.
struct AppFeatureView: View {
    let store: StoreOf<AppReducer>

    var body: some View {
        SearchFeatureView(
            store: store.scope(state: \.search, action: \.search)
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let model = PlaybackNowPlayingView.Model(
                store.scope(state: \.playback, action: \.playback)
            ) {
                PlaybackNowPlayingView(
                    model: model
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .task {
            await store.send(.task).finish()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.playback.isPlayerPresented },
                set: { store.send(.playback(.setPlayerPresented($0))) }
            )
        ) {
            PlaybackFeatureView(
                store: store.scope(state: \.playback, action: \.playback)
            )
        }
    }
}
