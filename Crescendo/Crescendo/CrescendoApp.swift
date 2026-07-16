import ComposableArchitecture
import SwiftUI

/// The Crescendo application entry point and composition root.
@main
struct CrescendoApp: App {
    let store = Store(
        initialState: AppFeature.State(
            registeredProviders: [.appleMusic],
            activeProviderID: nil,
            search: SearchFeature.State(
                query: "",
                status: .idle,
                playbackEligibility: .unknown
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: nil,
                status: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: .allEnabled
            ),
            isPlayerPresented: false
        )
    ) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            AppFeatureView(store: store)
        }
    }
}
