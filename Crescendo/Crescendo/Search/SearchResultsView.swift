import SwiftUI

/// Renders mutually exclusive search results and recovery states.
struct SearchResultsView: View {
    let status: SearchFeature.SearchStatus
    let query: String
    let onRetry: () -> Void

    var body: some View {
        switch status {
        case .idle:
            ContentUnavailableView(Locs.Search.emptyTitle, systemImage: "music.note")
        case .loading:
            ProgressView(Locs.Search.searching)
        case let .loaded(songs):
            if songs.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(songs) { song in
                    SongRow(song: song)
                }
            }
        case .denied, .restricted:
            ContentUnavailableView(
                Locs.Search.unavailableTitle,
                systemImage: "music.note.slash",
                description: Text(Locs.Search.videoStillAvailable)
            )
        case .failed:
            Button(Locs.Common.retry, action: onRetry)
        }
    }
}
