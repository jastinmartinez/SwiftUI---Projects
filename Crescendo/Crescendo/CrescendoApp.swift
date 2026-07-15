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
            )
        )
    ) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
