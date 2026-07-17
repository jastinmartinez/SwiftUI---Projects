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
        var pendingProviderID: ProviderID?
        var providerSwitchRequestID: UUID?
        var playbackTransition: PlaybackTransitionFeature.State?

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
            pendingProviderID: ProviderID?,
            providerSwitchRequestID: UUID?,
            playbackTransition: PlaybackTransitionFeature.State?
        ) {
            self.providerConnection = providerConnection
            self.search = search
            self.musicPlayback = musicPlayback
            self.isPlayerPresented = isPlayerPresented
            self.pendingProviderID = pendingProviderID
            self.providerSwitchRequestID = providerSwitchRequestID
            self.playbackTransition = playbackTransition
        }
    }

    enum Action: Equatable {
        case task
        case providerSelected(ProviderID)
        case providerConnection(ProviderConnectionFeature.Action)
        case resetProviderOwnedState(ProviderID)
        case providerSwitchPauseSucceeded(
            requestID: UUID,
            providerID: ProviderID
        )
        case providerSwitchPauseFailed(
            requestID: UUID,
            providerID: ProviderID
        )
        case search(SearchFeature.Action)
        case musicPlayback(MusicPlaybackFeature.Action)
        case playbackTransition(PlaybackTransitionFeature.Action)
        case setPlayerPresented(Bool)
    }

    enum CancelID {
        case providerSwitch
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.musicProvider) var musicProvider

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
                guard state.playbackTransition == nil else {
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
                    let hasPendingSwitch =
                        state.pendingProviderID != nil
                        || state.providerSwitchRequestID != nil
                    guard hasPendingSwitch else {
                        return .none
                    }
                    state.pendingProviderID = nil
                    state.providerSwitchRequestID = nil
                    return .cancel(id: CancelID.providerSwitch)
                }

                if state.pendingProviderID == providerID,
                    state.providerSwitchRequestID != nil
                {
                    return .none
                }

                if case .connected = state.providerConnection.connection {
                    let requestID = uuid()
                    state.pendingProviderID = providerID
                    state.providerSwitchRequestID = requestID
                    return .run { send in
                        do {
                            try await musicProvider.pause()
                            guard !Task.isCancelled else { return }
                            await send(
                                .providerSwitchPauseSucceeded(
                                    requestID: requestID,
                                    providerID: providerID
                                )
                            )
                        } catch {
                            guard !Task.isCancelled else { return }
                            await send(
                                .providerSwitchPauseFailed(
                                    requestID: requestID,
                                    providerID: providerID
                                )
                            )
                        }
                    }
                    .cancellable(id: CancelID.providerSwitch, cancelInFlight: true)
                }

                return .send(.providerConnection(.connect(provider.id)))

            case .providerSwitchPauseSucceeded(let requestID, let providerID):
                guard state.providerSwitchRequestID == requestID,
                    state.pendingProviderID == providerID,
                    state.providerConnection.provider(id: providerID) != nil
                else {
                    return .none
                }
                return .send(.providerConnection(.connect(providerID)))

            case .providerSwitchPauseFailed(let requestID, let providerID):
                guard state.providerSwitchRequestID == requestID,
                    state.pendingProviderID == providerID
                else {
                    return .none
                }
                state.pendingProviderID = nil
                state.providerSwitchRequestID = nil
                return .none

            case .providerConnection(
                .delegate(
                    .connectionStarted(let providerID, let providerChanged)
                )
            ):
                state.pendingProviderID = nil
                state.providerSwitchRequestID = nil
                guard providerChanged,
                    let provider = state.providerConnection.provider(
                        id: providerID
                    )
                else {
                    return .none
                }
                return .send(.resetProviderOwnedState(provider.id))

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
                    playbackEligibility: .unknown
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
                state.search.playbackEligibility =
                    connection.access?.playbackEligibility ?? .unknown
                return .none

            case .providerConnection:
                return .none

            case .search(.delegate(.songSelected(let song))):
                state.musicPlayback.selectedSong = song
                state.musicPlayback.playbackEligibility = state.search.playbackEligibility
                state.isPlayerPresented = true
                return .none

            case .search:
                return .none

            case .musicPlayback(.delegate(.playRequested(let itemID))):
                guard state.playbackTransition == nil,
                    state.providerSwitchRequestID == nil,
                    state.providerConnection.connection.access != nil
                else {
                    return .none
                }
                state.playbackTransition = .musicStart(
                    MusicStartFeature.State(itemID: itemID)
                )
                return .concatenate(
                    .send(.musicPlayback(.playbackStartAccepted)),
                    .send(.playbackTransition(.musicStart(.start)))
                )

            case .musicPlayback:
                return .none

            case .playbackTransition(
                .musicStart(.delegate(.succeeded(let itemID)))
            ):
                guard case .musicStart(let musicStartState) = state.playbackTransition,
                    musicStartState.itemID == itemID
                else {
                    return .none
                }
                state.playbackTransition = nil
                return .send(.musicPlayback(.transportFinished))

            case .playbackTransition(
                .musicStart(.delegate(.failed(let itemID, let error)))
            ):
                guard case .musicStart(let musicStartState) = state.playbackTransition,
                    musicStartState.itemID == itemID
                else {
                    return .none
                }
                state.playbackTransition = nil
                return .send(.musicPlayback(.transportFailed(error)))

            case .playbackTransition:
                return .none

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none
            }
        }
        .ifLet(\.playbackTransition, action: \.playbackTransition) {
            PlaybackTransitionFeature.body
        }
    }
}
