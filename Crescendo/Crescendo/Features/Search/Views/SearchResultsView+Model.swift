extension SearchResultsView {
    /// The immutable presentation contract for mutually exclusive search content.
    struct Model {
        let content: Content
        let onRetry: () -> Void
        let onSongTapped: (MusicItemID) -> Void
    }
}

extension SearchResultsView.Model {
    enum Content: Equatable {
        case idle
        case requiresProvider
        case loading
        case empty(query: String)
        case results(summary: String, rows: [SongRowView.Model])
        case failed
    }
}
