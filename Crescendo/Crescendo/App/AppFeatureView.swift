import ComposableArchitecture
import SwiftUI

/// The root store-connected view of Crescendo.
struct AppFeatureView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        let providerSelection = ProviderSelectionView.Model(store)

        VStack(spacing: 0) {
            SearchFeatureView(
                store: store.scope(state: \.search, action: \.search),
                providerSelection: providerSelection
            )
            if let song = store.musicPlayback.selectedSong {
                NowPlayingBarView(model: .init(store, song: song))
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
                providerName: store.activeProvider?.name
            )
        }
    }
}
