import ComposableArchitecture
import SwiftUI

/// Connects the search feature store to stateless search components.
struct SearchFeatureView: View {
    let store: StoreOf<SearchFeature>
    let providerSelection: ProviderSelectionView.Model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SearchHeaderView(
                        model: .init(
                            store,
                            providerSelection: providerSelection
                        )
                    )
                    SearchResultsView(
                        model: .init(
                            store,
                            providerName: providerSelection.activeProviderName
                        )
                    )
                    PlaybackEligibilityNoticeView(model: .init(store))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
