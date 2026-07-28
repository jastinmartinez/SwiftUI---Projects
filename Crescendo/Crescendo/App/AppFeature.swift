import ComposableArchitecture
import Foundation

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var providerConnection: ProviderConnectionFeature.State
        var search: SearchFeature.State
        var playback: PlaybackFeature.State
        var providerSwitch: ProviderSwitchFeature.State?
    }

    enum Action: Equatable {
        case task
        case providerSelected(ProviderID)
        case providerConnection(ProviderConnectionFeature.Action)
        case resetProviderOwnedState(ProviderID)
        case replaceProviderOwnedState(ProviderID)
        case providerSwitch(ProviderSwitchFeature.Action)
        case search(SearchFeature.Action)
        case playback(PlaybackFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.providerConnection, action: \.providerConnection) {
            ProviderConnectionFeature()
        }
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Scope(state: \.playback, action: \.playback) {
            PlaybackFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                return .send(.playback(.task))

            case let .providerSelected(providerID):
                guard state.playback.pendingPlaybackTransition == nil,
                      state.playback.pendingStatusChange == nil
                else {
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

                if case let .connected(currentProviderID, _) =
                    state.providerConnection.connection
                {
                    state.providerSwitch = ProviderSwitchFeature.State(
                        sourceProviderID: currentProviderID,
                        phase: .ready(targetProviderID: providerID)
                    )
                    return .send(.providerSwitch(.start))
                }

                return .send(.providerConnection(.connect(provider.id)))

            case let .providerSwitch(.delegate(.readyToConnect(providerID))):
                state.providerSwitch = nil
                return .send(.providerConnection(.connect(providerID)))

            case .providerSwitch(.delegate(.failed)),
                 .providerSwitch(.delegate(.cancelled)):
                state.providerSwitch = nil
                return .none

            case .providerSwitch:
                return .none

            case let .providerConnection(
                .delegate(
                    .connectionStarted(providerID, providerChanged)
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

            case let .resetProviderOwnedState(providerID):
                guard
                    let provider = state.providerConnection.provider(
                        id: providerID
                    )
                else {
                    return .none
                }
                return .concatenate(
                    .send(.search(.cancelSearch)),
                    .send(
                        .playback(
                            .reset(
                                providerID: provider.id,
                                capabilities: provider.musicCapabilities
                            )
                        )
                    )
                )

            case let .playback(.delegate(.resetCompleted(providerID))):
                if case let .connected(connectedProviderID, access) =
                    state.providerConnection.connection,
                    connectedProviderID == providerID,
                    access.authorization == .authorized
                {
                    return .concatenate(
                        .send(.replaceProviderOwnedState(providerID)),
                        .send(.playback(.task))
                    )
                }
                return .send(.replaceProviderOwnedState(providerID))

            case let .replaceProviderOwnedState(providerID):
                guard state.providerConnection.provider(id: providerID) != nil
                else {
                    return .none
                }
                let providerAccess: MusicProviderAccess?
                if case let .connected(connectedProviderID, access) =
                    state.providerConnection.connection,
                    connectedProviderID == providerID,
                    access.authorization == .authorized
                {
                    providerAccess = access
                } else {
                    providerAccess = nil
                }
                state.search = SearchFeature.State(
                    query: "",
                    status: .idle,
                    providerAccess: providerAccess,
                    providerID: providerID
                )
                return .none

            case let .providerConnection(
                .delegate(.connectionResolved(connection))
            ):
                if case let .connected(_, access) = connection,
                   access.authorization == .authorized
                {
                    state.search.providerAccess = access
                    return .send(.playback(.task))
                } else {
                    state.search.providerAccess = nil
                }
                return .none

            case .providerConnection:
                return .none

            case let .search(
                .delegate(
                    .trackTapped(track, loadedResults)
                )
            ):
                guard state.providerSwitch == nil,
                      case let .connected(_, access) =
                      state.providerConnection.connection,
                      access.authorization == .authorized
                else {
                    return .none
                }
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
        .ifLet(\.providerSwitch, action: \.providerSwitch) {
            ProviderSwitchFeature()
        }
    }
}

extension AppFeature.State {
    var requiresProviderSelection: Bool {
        providerConnection.connection == .disconnected
    }

    var activeProvider: ProviderDescriptor? {
        providerConnection.activeProvider
    }
}
