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
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: PlaybackTimelineFeature.State(
                        interaction: .idle
                    )
                ),
                isPlayerPresented: false,
                providerSwitch: nil,
                playbackCommand: nil
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.providerAccess = .appleMusic(appleMusicProvider)
            $0.providerSearch = .appleMusic(appleMusicProvider)
            $0.playbackControl = .appleMusic(appleMusicProvider)
            $0.playbackObservation = .appleMusic(appleMusicProvider)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppFeatureView(store: store)
        }
    }
}
