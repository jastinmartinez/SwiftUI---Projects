import ComposableArchitecture
import SwiftUI

/// The root store-connected view of Crescendo.
struct AppFeatureView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        SearchFeatureView(store: store.scope(state: \.search, action: \.search))
            .task { await store.send(.task).finish() }
    }
}
