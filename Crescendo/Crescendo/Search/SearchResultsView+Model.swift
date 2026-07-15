extension SearchResultsView {
    /// The immutable presentation contract for mutually exclusive search content.
    struct Model {
        let content: Content
        let onRetry: () -> Void
    }
}

extension SearchResultsView.Model {
    enum Content: Equatable {
        case idle
        case loading
        case empty(query: String)
        case results([SongRowView.Model])
        case unavailable
        case failed
    }
}
