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
        var playbackCommand: PlaybackCommandFeature.State?

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
            playbackCommand: PlaybackCommandFeature.State?
        ) {
            self.providerConnection = providerConnection
            self.search = search
            self.musicPlayback = musicPlayback
            self.isPlayerPresented = isPlayerPresented
            self.providerSwitch = providerSwitch
            self.playbackCommand = playbackCommand
        }
    }

    enum Action: Equatable {
        case task
        case providerSelected(ProviderID)
        case providerConnection(ProviderConnectionFeature.Action)
        case resetProviderOwnedState(ProviderID)
        case replaceProviderOwnedState(ProviderID)
        case providerSwitch(ProviderSwitchFeature.Action)
        case search(SearchFeature.Action)
        case musicPlayback(MusicPlaybackFeature.Action)
        case playbackCommand(PlaybackCommandFeature.Action)
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
                guard state.playbackCommand == nil else {
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
                return .concatenate(
                    .send(.musicPlayback(.timeline(.reset))),
                    .send(.replaceProviderOwnedState(provider.id))
                )

            case .replaceProviderOwnedState(let providerID):
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
                    capabilities: provider.musicCapabilities,
                    timeline: MusicPlaybackTimelineFeature.State(
                        interaction: .idle
                    )
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
                let playbackEligibility =
                    state
                    .providerConnection
                    .connection
                    .access?
                    .playbackEligibility ?? .unknown
                state.isPlayerPresented = true
                return .send(
                    .musicPlayback(
                        .songSelected(
                            song,
                            playbackEligibility: playbackEligibility
                        )
                    )
                )

            case .search:
                return .none

            case .musicPlayback(.delegate(let delegate)):
                let command: PlaybackCommandFeature.Command
                switch delegate {
                case .playRequested(let itemID):
                    command = .play(itemID)
                case .resumeRequested(let itemID):
                    command = .resume(itemID)
                }
                guard state.playbackCommand == nil,
                    state.providerSwitch == nil,
                    state.providerConnection.connection.access != nil
                else {
                    return .none
                }
                state.playbackCommand = PlaybackCommandFeature.State(
                    command: command
                )
                return .concatenate(
                    .send(.musicPlayback(.playbackCommandAccepted)),
                    .send(.playbackCommand(.start))
                )

            case .musicPlayback:
                return .none

            case .playbackCommand(.delegate(.succeeded(let command))):
                guard state.playbackCommand?.command == command else {
                    return .none
                }
                state.playbackCommand = nil
                return .send(.musicPlayback(.transportFinished))

            case .playbackCommand(
                .delegate(.failed(let command, let error))
            ):
                guard state.playbackCommand?.command == command else {
                    return .none
                }
                state.playbackCommand = nil
                return .send(.musicPlayback(.transportFailed(error)))

            case .playbackCommand:
                return .none

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none
            }
        }
        .ifLet(\.playbackCommand, action: \.playbackCommand) {
            PlaybackCommandFeature()
        }
        .ifLet(\.providerSwitch, action: \.providerSwitch) {
            ProviderSwitchFeature()
        }
    }
}
