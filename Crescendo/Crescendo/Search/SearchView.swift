import ComposableArchitecture
import SwiftUI

/// Connects the search feature store to stateless search components.
struct SearchView: View {
    let store: StoreOf<SearchFeature>

    var body: some View {
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

                SearchResultsView(
                    status: store.status,
                    query: store.query,
                    onRetry: { store.send(.retryButtonTapped) }
                )
                PlaybackEligibilityNotice(
                    eligibility: store.playbackEligibility,
                    showsUnknown: store.status.hasResults
                )
            }
            .navigationTitle(Locs.App.title)
        }
    }
}

private extension SearchFeature.SearchStatus {
    var hasResults: Bool {
        guard case let .loaded(songs) = self else { return false }
        return !songs.isEmpty
    }
}
