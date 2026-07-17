import SwiftUI
import UIKit

/// Renders mutually exclusive search results and recovery states.
struct SearchResultsView: View {
    let model: Model
    @Environment(\.openURL) private var openURL

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
        case .denied:
            ContentUnavailableView {
                Label(Locs.Search.deniedTitle, systemImage: "music.note.slash")
            } description: {
                Text(Locs.Search.deniedMessage)
            } actions: {
                Button(Locs.Search.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
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
