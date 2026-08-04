import ComposableArchitecture
import SwiftUI

/// The Crescendo application entry point and composition root owner.
@main
struct CrescendoApp: App {
    let store: StoreOf<AppReducer>

    init() {
        self.store = AppComposition.makeStore()
    }

    var body: some Scene {
        WindowGroup {
            AppFeatureView(store: store)
        }
    }
}
