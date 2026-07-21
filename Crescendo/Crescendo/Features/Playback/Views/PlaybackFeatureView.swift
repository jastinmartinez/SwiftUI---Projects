import ComposableArchitecture
import SwiftUI

/// Connects the playback store to its stateless presentation.
struct PlaybackFeatureView: View {
    let store: StoreOf<PlaybackFeature>
    let providerName: String?

    var body: some View {
        PlaybackView(model: .init(store, providerName: providerName))
    }
}
