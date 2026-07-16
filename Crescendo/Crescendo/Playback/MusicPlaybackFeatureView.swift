import ComposableArchitecture
import SwiftUI

/// Connects the playback store to its stateless presentation.
struct MusicPlaybackFeatureView: View {
    let store: StoreOf<MusicPlaybackFeature>

    var body: some View {
        MusicPlaybackView(model: .init(store))
    }
}
