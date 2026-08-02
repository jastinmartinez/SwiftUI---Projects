import ComposableArchitecture
import SwiftUI

/// Composes one aggregate search presentation from provider child state.
///
/// The feature shows shared progress while any provider is unresolved, reveals
/// nonempty provider rails as they arrive, and presents one empty state only
/// after every provider reaches a terminal state.
struct SearchFeatureView: View {
    @Bindable var store: StoreOf<SearchReducer>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SearchHeaderView(model: .init(store))
                        .padding(.horizontal, 20)

                    if store.isSearchInProgress {
                        ProgressView(Locs.Search.searching)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 20)
                    }

                    if store.hasCompletedSearchWithoutResults {
                        ContentUnavailableView.search
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .padding(.horizontal, 20)
                    }

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
