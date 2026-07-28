import ComposableArchitecture
import Foundation

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var search: SearchFeature.State
        var playback: PlaybackFeature.State
    }

    enum Action: Equatable {
        case task
        case search(SearchFeature.Action)
        case playback(PlaybackFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Scope(state: \.playback, action: \.playback) {
            PlaybackFeature()
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
