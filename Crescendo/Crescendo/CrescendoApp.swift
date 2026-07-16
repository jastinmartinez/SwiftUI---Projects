import AVFoundation
import ComposableArchitecture
import SwiftUI

/// The Crescendo application entry point and composition root.
@main
struct CrescendoApp: App {
    let store: StoreOf<AppFeature>
    let videoPlayer: AVPlayer

    init() {
        let videoPlayer = AVPlayer()
        let avPlayerController = AVPlayerController(player: videoPlayer)
        let videoPlayback = VideoPlaybackClient.live(
            controller: avPlayerController,
            itemLoader: .live
        )

        self.videoPlayer = videoPlayer
        self.store = Store(
            initialState: AppFeature.State(
                registeredProviders: [.appleMusic],
                activeProviderID: nil,
                search: SearchFeature.State(
                    query: "",
                    phase: .idle,
                    playbackEligibility: .unknown
                ),
                musicPlayback: MusicPlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled
                ),
                isPlayerPresented: false,
                video: nil,
                videoCloseRequestID: nil
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.videoPlayback = videoPlayback
        }
    }

    var body: some Scene {
        WindowGroup {
            AppFeatureView(
                store: store,
                videoPlayer: videoPlayer
            )
        }
    }
}
