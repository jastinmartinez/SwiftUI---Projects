import ComposableArchitecture
import Foundation

// Reducer-owned values that describe one provider results destination without
// introducing presentation, parent-coordination, or playback concerns.
extension ProviderSearchResultsReducer {
    /// Describes only the lifecycle of a continuation-page request.
    enum Status: Equatable {
        case idle
        case loading(requestID: UUID)
        case failed(MusicProviderError)
    }

    /// Facts emitted for the parent after this reducer validates a selection.
    enum Delegate: Equatable {
        case trackTapped(
            Track,
            loadedTracks: IdentifiedArrayOf<Track>
        )
    }
}
