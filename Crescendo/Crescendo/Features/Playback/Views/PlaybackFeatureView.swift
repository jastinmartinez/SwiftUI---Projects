import ComposableArchitecture
import SwiftUI

/// Forms the store-owning boundary for the expanded playback experience.
///
/// It adapts reducer state into `PlaybackView.Model` and passes the result to the
/// stateless playback hierarchy. Presentation decisions remain in the adapter.
struct PlaybackFeatureView: View {
    let store: StoreOf<PlaybackFeature>
    let providerName: String?

    var body: some View {
        PlaybackView(model: .init(store, providerName: providerName))
    }
}
