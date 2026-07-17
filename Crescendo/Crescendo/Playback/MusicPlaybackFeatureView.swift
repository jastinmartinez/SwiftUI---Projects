import ComposableArchitecture
import SwiftUI

/// Connects the playback store to its stateless presentation.
struct MusicPlaybackFeatureView: View {
    let store: StoreOf<MusicPlaybackFeature>
    let providerName: String?

    var body: some View {
        MusicPlaybackView(model: .init(store, providerName: providerName))
    }
}
