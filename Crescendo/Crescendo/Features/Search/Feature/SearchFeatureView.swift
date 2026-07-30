import ComposableArchitecture
import SwiftUI

/// The search feature boundary that composes stateless search views.
struct SearchFeatureView: View {
    let store: StoreOf<SearchReducer>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    SearchHeaderView(model: .init(store))
                    SearchResultsView(model: .init(store))
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
