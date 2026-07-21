/// Identifies whether a provider should begin or continue a search.
enum SearchPageRequest: Equatable, Sendable {
    case initial(query: String)
    case continuation(SearchCursor)
}
