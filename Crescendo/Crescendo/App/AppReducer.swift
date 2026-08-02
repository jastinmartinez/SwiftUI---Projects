import ComposableArchitecture
import Foundation

/// Owns application-level destinations and cross-feature coordination.
///
/// The reducer scopes Search, Library, and Playback, starts playback observation,
/// routes selected tracks into Playback, and selects Library when Search requests
/// it. It does not inspect provider state, build queues, perform searches, open
/// the Library importer, or render root presentation.
@Reducer
struct AppReducer {
    @ObservableState
    struct State: Equatable {
        var selectedTab: AppTab
        var search: SearchReducer.State
        var library: LibraryReducer.State
        var playback: PlaybackReducer.State
    }

    enum Action: Equatable {
        case task
        case selectedTabChanged(AppTab)
        case search(SearchReducer.Action)
        case library(LibraryReducer.Action)
        case playback(PlaybackReducer.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.search, action: \.search) {
            SearchReducer()
        }
        Scope(state: \.library, action: \.library) {
            LibraryReducer()
        }
        Scope(state: \.playback, action: \.playback) {
            PlaybackReducer()
        }
        Reduce { state, action in
            switch action {
            case .task:
                return .send(.playback(.task))

            case let .selectedTabChanged(selectedTab):
                state.selectedTab = selectedTab
                return .none

            case .search(.delegate(.libraryRequested)):
                state.selectedTab = .library
                return .none

            case let .search(
                .delegate(
                    .trackTapped(track, loadedTracks: loadedTracks)
                )
            ):
                return .send(
                    .playback(
                        .selectionReceived(
                            track.id,
                            loadedResults: loadedTracks
                        )
                    )
                )

            case let .library(
                .delegate(.trackTapped(track, loadedTracks))
            ):
                return .send(
                    .playback(
                        .selectionReceived(
                            track.id,
                            loadedResults: loadedTracks
                        )
                    )
                )

            case .search, .library, .playback:
                return .none
            }
        }
    }
}
