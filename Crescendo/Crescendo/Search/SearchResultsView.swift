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
        case .denied:
            ContentUnavailableView {
                Label(Locs.Search.deniedTitle, systemImage: "music.note.slash")
            } description: {
                Text(Locs.Search.deniedMessage)
            } actions: {
                Button(Locs.Search.openSettings, action: model.onOpenSettings)
                    .buttonStyle(.borderedProminent)
            }
        case .restricted:
            ContentUnavailableView(
                Locs.Search.restrictedTitle,
                systemImage: "music.note.slash",
                description: Text(Locs.Search.restrictedMessage)
            )
        case .failed:
            Button(Locs.Common.retry, action: model.onRetry)
        }
    }
}
