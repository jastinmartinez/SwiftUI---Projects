import ComposableArchitecture
import SwiftUI

/// Connects one presented results Store to the stateless vertical result list.
///
/// This boundary observes the frozen provider destination and routes its
/// continuation, retry, and selection actions. It owns no overview rail state,
/// shared query coordination, navigation policy, or playback queue.
struct ProviderSearchResultsFeatureView: View {
    let store: StoreOf<ProviderSearchResultsReducer>

    var body: some View {
        ScrollView {
            SearchResultListView(model: .init(store))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
