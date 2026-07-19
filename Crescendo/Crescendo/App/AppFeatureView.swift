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
            if let song = store.musicPlayback.selectedSong {
                NowPlayingBarView(model: .init(store, song: song))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .task {
            await store.send(.task).finish()
            await store.send(.musicPlayback(.task)).finish()
        }
        .sheet(
            isPresented: Binding(
                get: { store.isPlayerPresented },
                set: { store.send(.setPlayerPresented($0)) }
            )
        ) {
            MusicPlaybackFeatureView(
                store: store.scope(state: \.musicPlayback, action: \.musicPlayback),
                providerName: providerSelection.connectedProviderName
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
