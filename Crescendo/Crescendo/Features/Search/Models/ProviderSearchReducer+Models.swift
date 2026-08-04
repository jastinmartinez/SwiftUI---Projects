import ComposableArchitecture
import Foundation

// Reducer-owned values for one provider's first-page search lifecycle.
//
// These values describe one provider's lifecycle and validated result facts
// for the parent. They contain no shared query, destination pagination,
// navigation, presentation, or playback policy.
extension ProviderSearchReducer {
    /// Describes whether this provider is inactive, searching, loaded, or
    /// failed.
    enum Status: Equatable {
        case inactive
        case searching(requestID: UUID)
        case loaded(Page)
        case failed(MusicProviderError)
    }

    /// Preserves the provider's immutable first page for rail presentation and
    /// destination creation.
    struct Page: Equatable {
        let tracks: IdentifiedArrayOf<Track>
        let nextCursor: SearchCursor?
    }

    /// Facts emitted after this reducer validates a result interaction.
    enum Delegate: Equatable {
        case seeAllRequested(Page)
        case trackTapped(
            Track,
            loadedTracks: IdentifiedArrayOf<Track>
        )
    }
}
