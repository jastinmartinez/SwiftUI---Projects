import ComposableArchitecture
import Foundation

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var providerConnection: ProviderConnectionFeature.State
        var search: SearchFeature.State
        var musicPlayback: MusicPlaybackFeature.State
        var isPlayerPresented: Bool
        var providerSwitch: ProviderSwitchFeature.State?
        var playbackStart: PlaybackStartFeature.State?

        var requiresProviderSelection: Bool {
            providerConnection.connection == .disconnected
        }

        var activeProvider: ProviderDescriptor? {
            providerConnection.activeProvider
        }

        init(
            providerConnection: ProviderConnectionFeature.State,
            search: SearchFeature.State,
            musicPlayback: MusicPlaybackFeature.State,
            isPlayerPresented: Bool,
            providerSwitch: ProviderSwitchFeature.State?,
            playbackStart: PlaybackStartFeature.State?
        ) {
            self.providerConnection = providerConnection
            self.search = search
            self.musicPlayback = musicPlayback
            self.isPlayerPresented = isPlayerPresented
            self.providerSwitch = providerSwitch
            self.playbackStart = playbackStart
        }
    }

    enum Action: Equatable {
        case task
        case providerSelected(ProviderID)
        case providerConnection(ProviderConnectionFeature.Action)
        case resetProviderOwnedState(ProviderID)
        case providerSwitch(ProviderSwitchFeature.Action)
        case search(SearchFeature.Action)
        case musicPlayback(MusicPlaybackFeature.Action)
        case playbackStart(PlaybackStartFeature.Action)
        case setPlayerPresented(Bool)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.providerConnection, action: \.providerConnection) {
            ProviderConnectionFeature()
        }
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Scope(state: \.musicPlayback, action: \.musicPlayback) {
            MusicPlaybackFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                return .none

            case .providerSelected(let providerID):
                guard state.playbackStart == nil else {
                    return .none
                }
                guard
                    let provider = state.providerConnection.provider(
                        id: providerID
                    )
                else {
                    return .none
                }

                if providerID == state.providerConnection.connection.providerID {
                    guard state.providerSwitch != nil else { return .none }
                    return .send(.providerSwitch(.cancel))
                }

                if state.providerSwitch != nil {
                    return .send(.providerSwitch(.targetChanged(providerID)))
                }

                if case .connected(let currentProviderID, _) =
                    state.providerConnection.connection
                {
                    state.providerSwitch = ProviderSwitchFeature.State(
                        sourceProviderID: currentProviderID,
                        phase: .ready(targetProviderID: providerID)
                    )
                    return .send(.providerSwitch(.start))
                }

                return .send(.providerConnection(.connect(provider.id)))

            case .providerSwitch(.delegate(.readyToConnect(let providerID))):
                state.providerSwitch = nil
                return .send(.providerConnection(.connect(providerID)))

            case .providerSwitch(.delegate(.failed)),
                .providerSwitch(.delegate(.cancelled)):
                state.providerSwitch = nil
                return .none

            case .providerSwitch:
                return .none

            case .providerConnection(
                .delegate(
                    .connectionStarted(let providerID, let providerChanged)
                )
            ):
                guard providerChanged,
                    let provider = state.providerConnection.provider(
                        id: providerID
                    )
                else {
                    return .none
                }
                return .send(.resetProviderOwnedState(provider.id))

            case .providerConnection(.startConnection):
                state.search.providerAccess = nil
                return .none

            case .resetProviderOwnedState(let providerID):
                guard
                    let provider = state.providerConnection.provider(
                        id: providerID
                    )
                else {
                    return .none
                }
                state.search = SearchFeature.State(
                    query: "",
                    phase: .idle,
                    providerAccess: nil
                )
                state.musicPlayback = MusicPlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: provider.musicCapabilities
                )
                state.isPlayerPresented = false
                return .none

            case .providerConnection(
                .delegate(.connectionResolved(let connection))
            ):
                if case .connected(_, let access) = connection,
                    access.authorization == .authorized
                {
                    state.search.providerAccess = access
                } else {
                    state.search.providerAccess = nil
                }
                return .none

            case .providerConnection:
                return .none

            case .search(.delegate(.songSelected(let song))):
                state.musicPlayback.selectedSong = song
                state.musicPlayback.playbackEligibility =
                    state
                    .providerConnection
                    .connection
                    .access?
                    .playbackEligibility ?? .unknown
                state.isPlayerPresented = true
                return .none

            case .search:
                return .none

            case .musicPlayback(.delegate(.playRequested(let itemID))):
                guard state.playbackStart == nil,
                    state.providerSwitch == nil,
                    state.providerConnection.connection.access != nil
                else {
                    return .none
                }
                state.playbackStart = PlaybackStartFeature.State(itemID: itemID)
                return .concatenate(
                    .send(.musicPlayback(.playbackStartAccepted)),
                    .send(.playbackStart(.start))
                )

            case .musicPlayback:
                return .none

            case .playbackStart(.delegate(.succeeded(let itemID))):
                guard state.playbackStart?.itemID == itemID else {
                    return .none
                }
                state.playbackStart = nil
                return .send(.musicPlayback(.transportFinished))

            case .playbackStart(.delegate(.failed(let itemID, let error))):
                guard state.playbackStart?.itemID == itemID else {
                    return .none
                }
                state.playbackStart = nil
                return .send(.musicPlayback(.transportFailed(error)))

            case .playbackStart:
                return .none

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none
            }
        }
        .ifLet(\.playbackStart, action: \.playbackStart) {
            PlaybackStartFeature()
        }
        .ifLet(\.providerSwitch, action: \.providerSwitch) {
            ProviderSwitchFeature()
        }
    }
}
