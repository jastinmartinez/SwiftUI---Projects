import SwiftUI

/// Renders mutually exclusive search results and recovery states.
struct SearchResultsView: View {
    let model: Model

    var body: some View {
        switch model.content {
        case .idle:
            ContentUnavailableView(Locs.Search.emptyTitle, systemImage: "music.note")
        case .requiresProvider:
            ContentUnavailableView(
                Locs.Search.requiresProviderTitle,
                systemImage: "music.note",
                description: Text(Locs.Search.requiresProviderMessage)
            )
        case .loading:
            ProgressView(Locs.Search.searching)
        case .empty(let query):
            ContentUnavailableView.search(text: query)
        case .results(let results):
            SearchResultListView(model: results)
        case .failed:
            Button(Locs.Common.retry, action: model.onRetry)
        }
    }
}

extension SearchResultsView {
    /// The immutable presentation contract for mutually exclusive search content.
    struct Model {
        let content: Content
        let onRetry: () -> Void
    }
}

extension SearchResultsView.Model {
    enum Content {
        case idle
        case requiresProvider
        case loading
        case empty(query: String)
        case results(SearchResultListView.Model)
        case failed
    }
}
