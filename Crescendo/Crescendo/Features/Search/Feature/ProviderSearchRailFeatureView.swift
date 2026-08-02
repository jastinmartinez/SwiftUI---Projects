import ComposableArchitecture
import SwiftUI

/// Connects one provider child Store to its stateless horizontal rail.
///
/// This boundary observes only one provider's first-page state and forwards its
/// actions. Shared-query coordination, pagination, navigation, App routing, and
/// playback remain outside this feature view.
struct ProviderSearchRailFeatureView: View {
    let store: StoreOf<ProviderSearchReducer>

    var body: some View {
        ProviderSearchRailView(model: .init(store))
    }
}
