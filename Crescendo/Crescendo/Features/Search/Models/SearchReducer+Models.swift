import ComposableArchitecture

/// Reducer-owned values emitted after Search validates a child interaction.
///
/// These facts form the Search-to-App boundary. They carry no tab-selection,
/// playback, provider-request, pagination, or presentation policy.
extension SearchReducer {
    enum Delegate: Equatable {
        case libraryRequested
        case trackTapped(
            Track,
            loadedTracks: IdentifiedArrayOf<Track>
        )
    }
}
