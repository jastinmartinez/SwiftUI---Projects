/// One immutable provider-neutral page of search results and its continuation.
struct SearchPage: Equatable, Sendable {
    let tracks: [Track]
    let nextCursor: SearchCursor?
}
