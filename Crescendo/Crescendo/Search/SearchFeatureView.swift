import ComposableArchitecture
import SwiftUI

/// Connects the search feature store to stateless search components.
struct SearchFeatureView: View {
    let store: StoreOf<SearchFeature>
    let providerName: String?

    var body: some View {
        let resultsModel = SearchResultsView.Model(store)
        let eligibilityModel = PlaybackEligibilityNoticeView.Model(store)

        NavigationStack {
            List {
                HStack {
                    TextField(
                        Locs.Search.prompt,
                        text: Binding(
                            get: { store.query },
                            set: { store.send(.queryChanged($0)) }
                        )
                    )
                    .submitLabel(.search)
                    .onSubmit { store.send(.submitButtonTapped) }

                    Button(Locs.Search.action) {
                        store.send(.submitButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                }

                SearchResultsView(model: resultsModel)
                PlaybackEligibilityNoticeView(model: eligibilityModel)
            }
            .navigationTitle(Locs.App.title)
            .toolbar {
                if let providerName {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(providerName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.tint.opacity(0.12), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
    }
}
