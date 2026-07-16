import ComposableArchitecture
import SwiftUI

/// Connects the search feature store to stateless search components.
struct SearchFeatureView: View {
    let store: StoreOf<SearchFeature>

    var body: some View {
        let resultsModel = SearchResultsView.Model(store)
        let eligibilityModel = PlaybackEligibilityNoticeView.Model(store)

        NavigationStack {
            List {
                TextField(
                    Locs.Search.prompt,
                    text: Binding(
                        get: { store.query },
                        set: { store.send(.queryChanged($0)) }
                    )
                )
                .submitLabel(.search)
                .onSubmit { store.send(.submitButtonTapped) }

                SearchResultsView(model: resultsModel)
                PlaybackEligibilityNoticeView(model: eligibilityModel)
            }
            .navigationTitle(Locs.App.title)
        }
    }
}
