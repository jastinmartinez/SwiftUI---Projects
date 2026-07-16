import ComposableArchitecture
import SwiftUI

/// Connects Video feature state to the URL input and AVKit bridge.
struct VideoPlaybackFeatureView: View {
    let store: StoreOf<VideoPlaybackFeature>
    let videoPlayerView: VideoPlayerView
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoURLInputView(model: .init(store))

                if store.loadedVideoURL != nil {
                    videoPlayerView
                        .aspectRatio(16 / 9, contentMode: .fit)
                }

                Spacer()
            }
            .padding()
            .navigationTitle(Locs.Video.title)
            .toolbar {
                Button(
                    Locs.Video.close,
                    action: onClose
                )
            }
            .task { await store.send(.task).finish() }
            .onDisappear { store.send(.routeExited) }
        }
    }
}
