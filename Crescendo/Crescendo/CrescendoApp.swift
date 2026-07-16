import ComposableArchitecture
import SwiftUI

/// The Crescendo application entry point and composition root.
@main
struct CrescendoApp: App {
    let store: StoreOf<AppFeature>
    let videoPlayerSession: AVPlayerSession

    init() {
        let videoPlayerSession = AVPlayerSession.live()
        let videoPlayback = VideoPlaybackClient.live(
            session: videoPlayerSession,
            itemLoader: .live
        )

        self.videoPlayerSession = videoPlayerSession
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
                videoPlayerSession: videoPlayerSession
            )
        }
    }
}
