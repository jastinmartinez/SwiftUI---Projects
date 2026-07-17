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
            pendingProviderID: ProviderID?,
            providerSwitchRequestID: UUID?,
            playbackStart: PlaybackStartFeature.State?
        ) {
            self.providerConnection = providerConnection
            self.search = search
            self.musicPlayback = musicPlayback
            self.isPlayerPresented = isPlayerPresented
            self.pendingProviderID = pendingProviderID
            self.providerSwitchRequestID = providerSwitchRequestID
            self.playbackStart = playbackStart
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
        case playbackStart(PlaybackStartFeature.Action)
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
                guard state.playbackStart == nil,
                    state.providerSwitchRequestID == nil,
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
    }
}
