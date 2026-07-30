import ComposableArchitecture
import Foundation

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppReducer {
    @ObservableState
    struct State: Equatable {
        var search: SearchReducer.State
        var playback: PlaybackReducer.State
    }

    enum Action: Equatable {
        case task
        case search(SearchReducer.Action)
        case playback(PlaybackReducer.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.search, action: \.search) {
            SearchReducer()
        }
        Scope(state: \.playback, action: \.playback) {
            PlaybackReducer()
        }
        Reduce { _, action in
            switch action {
            case .task:
                return .send(.playback(.task))

            case .search(
                .delegate(
                    .trackTapped(let track, let loadedResults)
                )
            ):
                return .send(
                    .playback(
                        .selectionReceived(
                            track.id,
                            loadedResults: loadedResults
                        )
                    )
                )

            case .search, .playback:
                return .none
            }
        }
    }
}
