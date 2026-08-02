import ComposableArchitecture
import Foundation

/// Reducer-owned values for one provider's first-page search lifecycle.
///
/// These values describe mutually exclusive rail state and validated facts for
/// the parent. They contain no shared query, destination pagination, navigation,
/// presentation, App routing, or playback policy.
extension ProviderSearchReducer {
    /// Describes whether this provider rail is inactive, searching, loaded, or
    /// failed. This is the rail's only activation representation.
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

    /// Facts emitted after this reducer validates a rail interaction.
    enum Delegate: Equatable {
        case activationRequested
        case retryRequested
        case seeAllRequested(Page)
        case libraryRequested
        case trackTapped(
            Track,
            loadedTracks: IdentifiedArrayOf<Track>
        )
    }
}
