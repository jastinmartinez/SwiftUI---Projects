import ComposableArchitecture

/// Owns the confirmed playback queue order and current item identity.
@Reducer
struct PlaybackQueueFeature {
    @ObservableState
    struct State: Equatable {
        var songs: IdentifiedArrayOf<SongSummary>
        var currentItemID: MusicItemID?
    }

    enum Action: Equatable {
        case replace(
            IdentifiedArrayOf<SongSummary>,
            startingAt: MusicItemID
        )
        case currentItemObserved(MusicItemID?)
        case reset
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .replace(let songs, let startingItemID):
                guard songs[id: startingItemID] != nil else {
                    return .none
                }
                state.songs = songs
                state.currentItemID = startingItemID
                return .none

            case .currentItemObserved(let itemID):
                guard let itemID,
                    state.songs[id: itemID] != nil
                else { return .none }
                state.currentItemID = itemID
                return .none

            case .reset:
                state.songs = []
                state.currentItemID = nil
                return .none
            }
        }
    }
}

extension PlaybackQueueFeature.State {
    var currentItem: SongSummary? {
        guard let currentItemID else { return nil }
        return songs[id: currentItemID]
    }
}
