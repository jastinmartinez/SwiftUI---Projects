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
        case .results(let summary, let rows):
            SearchResultListView(
                model: .init(
                    summary: summary,
                    rows: rows,
                    onSongTapped: model.onSongTapped
                )
            )
        case .failed:
            Button(Locs.Common.retry, action: model.onRetry)
        }
    }
}
