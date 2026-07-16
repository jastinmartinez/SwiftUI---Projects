import AVFoundation
import ComposableArchitecture
import SwiftUI

/// The root store-connected view of Crescendo.
struct AppFeatureView: View {
    let store: StoreOf<AppFeature>
    let videoPlayer: AVPlayer

    var body: some View {
        VStack(spacing: 0) {
            SearchFeatureView(store: store.scope(state: \.search, action: \.search))
            if let song = store.musicPlayback.selectedSong {
                NowPlayingBarView(model: .init(store, song: song))
            }
            Button(Locs.Video.openAction) {
                store.send(.openVideoButtonTapped)
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
                store: store.scope(state: \.musicPlayback, action: \.musicPlayback)
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { store.video != nil },
                set: { if !$0 { store.send(.closeVideoRequested) } }
            )
        ) {
            if let videoStore = store.scope(state: \.video, action: \.video) {
                VideoPlaybackFeatureView(
                    store: videoStore,
                    player: videoPlayer
                )
            }
        }
    }
}
