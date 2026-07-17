import ComposableArchitecture
import SwiftUI

/// The Crescendo application entry point and composition root.
@main
struct CrescendoApp: App {
    let store: StoreOf<AppFeature>

    init() {
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
                pendingProviderID: nil,
                providerSwitchRequestID: nil,
                playbackTransition: nil
            )
        ) {
            AppFeature()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppFeatureView(store: store)
        }
    }
}
