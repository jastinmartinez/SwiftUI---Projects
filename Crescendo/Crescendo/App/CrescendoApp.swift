import ComposableArchitecture
import SwiftUI

/// The Crescendo application entry point and composition root.
@main
struct CrescendoApp: App {
    let store: StoreOf<AppFeature>

    init() {
        let appleMusicProvider = AppleMusicProvider()

        self.store = Store(
            initialState: AppFeature.State(
                providerConnection: ProviderConnectionFeature.State(
                    providers: [.appleMusic],
                    connection: .disconnected
                ),
                search: SearchFeature.State(
                    query: "",
                    status: .idle,
                    providerAccess: nil
                ),
                playback: PlaybackFeature.State(
                    providerID: nil,
                    queue: PlaybackQueueFeature.State(
                        songs: [],
                        currentItemID: nil,
                        repeatMode: .off,
                        shuffleMode: .off,
                        pendingQueueTransition: nil,
                        pendingRepeatChange: nil,
                        pendingShuffleChange: nil
                    ),
                    status: .idle,
                    failure: nil,
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: PlaybackTimelineFeature.State(
                        confirmedPosition: 0,
                        interaction: .idle
                    ),
                    pendingOperation: nil,
                    pendingProviderReset: nil,
                    isPlayerPresented: false
                ),
                providerSwitch: nil
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.providerAccess = .appleMusic(appleMusicProvider)
            $0.providerSearch = .appleMusic(appleMusicProvider)
            $0.playbackTransport = .appleMusic(appleMusicProvider)
            $0.playbackTimeline = .appleMusic(appleMusicProvider)
            $0.playbackQueue = .appleMusic(appleMusicProvider)
            $0.playbackObservation = .appleMusic(appleMusicProvider)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppFeatureView(store: store)
        }
    }
}
