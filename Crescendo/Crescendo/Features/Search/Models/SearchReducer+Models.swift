import ComposableArchitecture

// Reducer-owned values emitted after Search validates a child interaction.
//
// These facts form the Search-to-App boundary. They carry no tab-selection,
// playback, provider-request, pagination, or presentation policy.
extension SearchReducer {
    enum Delegate: Equatable {
        case trackTapped(
            Track,
            loadedTracks: IdentifiedArrayOf<Track>
        )
    }
}

// Aggregate search facts derived from the provider children.
//
// These values let the parent presentation describe one user-facing search
// without exposing provider-specific loading or failure states. They store no
// duplicate lifecycle state and do not decide how progress or an empty result
// is rendered.
extension SearchReducer.State {
    var isSearchInProgress: Bool {
        guard submittedQuery != nil else { return false }

        for provider in providers {
            switch provider.status {
            case .inactive, .searching:
                return true
            case .loaded, .failed:
                continue
            }
        }

        return false
    }

    var hasSearchResults: Bool {
        for provider in providers {
            guard case .loaded(let page) = provider.status else {
                continue
            }
            if !page.tracks.isEmpty {
                return true
            }
        }

        return false
    }

    var hasCompletedSearchWithoutResults: Bool {
        submittedQuery != nil
            && !isSearchInProgress
            && !hasSearchResults
    }
}
