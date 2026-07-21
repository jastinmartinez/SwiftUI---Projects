import ComposableArchitecture
import SwiftUI

/// The root store-connected view of Crescendo.
struct AppFeatureView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        let providerSelection = ProviderSelectionView.Model(store)

        SearchFeatureView(
            store: store.scope(state: \.search, action: \.search),
            providerSelection: providerSelection
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let song = store.playback.queue.currentItem {
                PlaybackNowPlayingView(model: .init(store, song: song))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .task {
            await store.send(.task).finish()
            await store.send(.playback(.task)).finish()
        }
        .sheet(
            isPresented: Binding(
                get: { store.isPlayerPresented },
                set: { store.send(.setPlayerPresented($0)) }
            )
        ) {
            PlaybackFeatureView(
                store: store.scope(state: \.playback, action: \.playback),
                providerName: providerSelection.connectedProviderName
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
