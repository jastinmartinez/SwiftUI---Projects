import SwiftUI

/// Renders mutually exclusive search results and recovery states.
struct SearchResultsView: View {
    let model: Model

    var body: some View {
        switch model.content {
        case .idle:
            ContentUnavailableView(
                model.strings.emptyTitle,
                systemImage: "music.note"
            )
        case .loading:
            ProgressView(model.strings.searching)
        case .empty(let query):
            ContentUnavailableView.search(text: query)
        case .results(let results):
            SearchResultListView(model: results)
        case .failed:
            Button(model.strings.retry, action: model.onRetry)
        }
    }
}

extension SearchResultsView {
    /// The immutable presentation contract for mutually exclusive search content.
    struct Model {
        let content: Content
        let strings: Strings
        let onRetry: () -> Void
    }
}

extension SearchResultsView.Model {
    enum Content {
        case idle
        case loading
        case empty(query: String)
        case results(SearchResultListView.Model)
        case failed
    }

    /// Contains every localized string rendered by the search results state.
    struct Strings {
        let emptyTitle: String
        let searching: String
        let retry: String
    }
}
