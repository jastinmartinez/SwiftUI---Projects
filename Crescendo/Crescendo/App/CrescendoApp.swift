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
                    phase: .idle,
                    providerAccess: nil
                ),
                musicPlayback: MusicPlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: MusicPlaybackTimelineFeature.State(
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
            $0.musicProvider = .appleMusic(appleMusicProvider)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppFeatureView(store: store)
        }
    }
}
