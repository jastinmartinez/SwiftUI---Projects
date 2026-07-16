import AVFoundation
import ComposableArchitecture
import SwiftUI

/// Connects Video feature state to the URL input and AVKit bridge.
struct VideoPlaybackFeatureView: View {
    let store: StoreOf<VideoPlaybackFeature>
    let player: AVPlayer

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoURLInputView(model: .init(store))

                if store.loadedVideoURL != nil {
                    VideoPlayerView(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                }

                Spacer()
            }
            .padding()
            .navigationTitle(Locs.Video.title)
            .toolbar {
                Button(Locs.Video.close) {
                    store.send(.closeButtonTapped)
                }
            }
            .task { await store.send(.task).finish() }
            .onDisappear { store.send(.routeExited) }
        }
    }
}
