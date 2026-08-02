import ComposableArchitecture
import SwiftUI

/// The search feature boundary that composes stateless search views.
struct SearchFeatureView: View {
    @Bindable var store: StoreOf<SearchReducer>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SearchHeaderView(model: .init(store))
                        .padding(.horizontal, 20)

                    LazyVStack(spacing: 28) {
                        ForEach(
                            store.scope(\.providers, action: \.providers)
                        ) { providerStore in
                            ProviderSearchRailFeatureView(
                                store: providerStore
                            )
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(
                item: $store.scope(\.$destination, action: \.destination)
            ) { destinationStore in
                ProviderSearchResultsFeatureView(store: destinationStore)
            }
        }
    }
}
