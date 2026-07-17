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
        case .results(let rows):
            ForEach(rows) { row in
                Button {
                    model.onSongTapped(row.songID)
                } label: {
                    SongRowView(model: row)
                }
                .buttonStyle(.plain)
            }
        case .unavailable:
            ContentUnavailableView(
                Locs.Search.unavailableTitle,
                systemImage: "music.note.slash"
            )
        case .failed:
            Button(Locs.Common.retry, action: model.onRetry)
        }
    }
}
