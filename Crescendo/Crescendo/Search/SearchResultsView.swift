import SwiftUI

/// Renders mutually exclusive search results and recovery states.
struct SearchResultsView: View {
    let model: Model

    var body: some View {
        switch model.content {
        case .idle:
            ContentUnavailableView(Locs.Search.emptyTitle, systemImage: "music.note")
        case .loading:
            ProgressView(Locs.Search.searching)
        case let .empty(query):
            ContentUnavailableView.search(text: query)
        case let .results(rows):
            ForEach(rows) { row in
                SongRowView(model: row)
            }
        case .unavailable:
            ContentUnavailableView(
                Locs.Search.unavailableTitle,
                systemImage: "music.note.slash",
                description: Text(Locs.Search.videoStillAvailable)
            )
        case .failed:
            Button(Locs.Common.retry, action: model.onRetry)
        }
    }
}
