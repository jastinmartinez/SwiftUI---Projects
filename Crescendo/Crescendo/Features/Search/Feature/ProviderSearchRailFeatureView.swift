import ComposableArchitecture
import SwiftUI

/// Connects one provider child Store to an optional result rail.
///
/// A provider without nonempty first-page results renders no view. Shared-query
/// coordination, aggregate loading and empty presentation, pagination,
/// navigation, and playback remain outside this feature view.
struct ProviderSearchRailFeatureView: View {
    let store: StoreOf<ProviderSearchReducer>

    var body: some View {
        if let model = ProviderSearchRailView.Model(store) {
            ProviderSearchRailView(model: model)
        }
    }
}
