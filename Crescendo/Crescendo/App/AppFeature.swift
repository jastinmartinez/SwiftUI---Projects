import ComposableArchitecture

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        let registeredProviders: [MusicProviderDescriptor]
        var activeProviderID: MusicProviderID?
        var search: SearchFeature.State
        var musicPlayback: MusicPlaybackFeature.State
        var isPlayerPresented: Bool

        var requiresProviderSelection: Bool {
            registeredProviders.count > 1 && activeProviderID == nil
        }

        init(
            registeredProviders: [MusicProviderDescriptor],
            activeProviderID: MusicProviderID?,
            search: SearchFeature.State,
            musicPlayback: MusicPlaybackFeature.State,
            isPlayerPresented: Bool
        ) {
            self.registeredProviders = registeredProviders
            self.activeProviderID = activeProviderID
            self.search = search
            self.musicPlayback = musicPlayback
            self.isPlayerPresented = isPlayerPresented
        }
    }

    enum Action: Equatable {
        case task
        case providerSelected(MusicProviderID)
        case search(SearchFeature.Action)
        case musicPlayback(MusicPlaybackFeature.Action)
        case setPlayerPresented(Bool)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Scope(state: \.musicPlayback, action: \.musicPlayback) {
            MusicPlaybackFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                if state.activeProviderID == nil, state.registeredProviders.count == 1 {
                    state.activeProviderID = state.registeredProviders[0].id
                }
                return .none

            case .providerSelected(let providerID):
                let isRegisteredProvider = state.registeredProviders.contains(
                    where: { $0.id == providerID }
                )
                guard isRegisteredProvider else {
                    return .none
                }
                state.activeProviderID = providerID
                return .none

            case .search(.delegate(.songSelected(let song))):
                state.musicPlayback.selectedSong = song
                state.musicPlayback.playbackEligibility = state.search.playbackEligibility
                state.isPlayerPresented = true
                return .none

            case .search:
                return .none

            case .musicPlayback:
                return .none

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none
            }
        }
    }
}
