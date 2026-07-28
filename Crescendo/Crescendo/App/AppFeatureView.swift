import ComposableArchitecture
import SwiftUI

/// The root store-connected view of Crescendo.
struct AppFeatureView: View {
    let store: StoreOf<AppFeature>

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
        .sheet(
            isPresented: Binding(
                get: { store.playback.isPlayerPresented },
                set: { store.send(.playback(.setPlayerPresented($0))) }
            )
        ) {
            PlaybackFeatureView(
                store: store.scope(state: \.playback, action: \.playback)
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
