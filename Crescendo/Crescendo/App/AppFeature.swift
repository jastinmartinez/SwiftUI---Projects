import ComposableArchitecture
import Foundation
import UIKit

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        let registeredProviders: [ProviderDescriptor]
        var providerConnection: ProviderConnection
        var search: SearchFeature.State
        var musicPlayback: MusicPlaybackFeature.State
        var isPlayerPresented: Bool
        var pendingProviderID: ProviderID?
        var providerSwitchRequestID: UUID?
        var playbackTransition: PlaybackTransition?

        var requiresProviderSelection: Bool {
            providerConnection == .disconnected
        }

        var activeProvider: ProviderDescriptor? {
            registeredProviders.first { $0.id == providerConnection.providerID }
        }

        init(
            registeredProviders: [ProviderDescriptor],
            providerConnection: ProviderConnection,
            search: SearchFeature.State,
            musicPlayback: MusicPlaybackFeature.State,
            isPlayerPresented: Bool,
            pendingProviderID: ProviderID?,
            providerSwitchRequestID: UUID?,
            playbackTransition: PlaybackTransition?
        ) {
            self.registeredProviders = registeredProviders
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
        case providerRetryTapped
        case providerOpenSettingsTapped
        case providerSwitchPauseSucceeded(
            requestID: UUID,
            providerID: ProviderID
        )
        case providerSwitchPauseFailed(
            requestID: UUID,
            providerID: ProviderID
        )
        case providerCurrentAccessResponse(
            requestID: UUID,
            providerID: ProviderID,
            access: MusicProviderAccess
        )
        case providerRequestedAccessResponse(
            requestID: UUID,
            providerID: ProviderID,
            access: MusicProviderAccess
        )
        case search(SearchFeature.Action)
        case musicPlayback(MusicPlaybackFeature.Action)
        case musicStartSucceeded(MusicItemID)
        case musicStartFailed(MusicItemID, MusicProviderError)
        case setPlayerPresented(Bool)
    }

    enum CancelID {
        case providerAccess
        case providerSwitch
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.musicProvider) var musicProvider
    @Dependency(\.openURL) var openURL

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
                return .none

            case .providerSelected(let providerID):
                guard state.playbackTransition == nil else {
                    return .none
                }
                guard
                    let provider = state.registeredProviders.first(
                        where: { $0.id == providerID }
                    )
                else {
                    return .none
                }

                if providerID == state.providerConnection.providerID {
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

                if case .connected = state.providerConnection {
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

                return beginAccessResolution(state: &state, provider: provider)

            case .providerRetryTapped:
                guard case .failed(let providerID) = state.providerConnection,
                    let provider = state.registeredProviders.first(
                        where: { $0.id == providerID }
                    )
                else {
                    return .none
                }
                return beginAccessResolution(state: &state, provider: provider)

            case .providerOpenSettingsTapped:
                return .run { _ in
                    let settingsURL = UIApplication.openSettingsURLString
                    guard let url = URL(string: settingsURL) else { return }
                    await openURL(url)
                }

            case .providerSwitchPauseSucceeded(let requestID, let providerID):
                guard state.providerSwitchRequestID == requestID,
                    state.pendingProviderID == providerID,
                    let provider = state.registeredProviders.first(
                        where: { $0.id == providerID }
                    )
                else {
                    return .none
                }
                return beginAccessResolution(state: &state, provider: provider)

            case .providerSwitchPauseFailed(let requestID, let providerID):
                guard state.providerSwitchRequestID == requestID,
                    state.pendingProviderID == providerID
                else {
                    return .none
                }
                state.pendingProviderID = nil
                state.providerSwitchRequestID = nil
                return .none

            case .providerCurrentAccessResponse(
                let requestID,
                let providerID,
                let access
            ):
                let expectedConnection = ProviderConnection.connecting(
                    providerID: providerID,
                    requestID: requestID
                )
                guard state.providerConnection == expectedConnection else {
                    return .none
                }

                guard access.authorization == .notDetermined else {
                    resolveConnection(
                        state: &state,
                        providerID: providerID,
                        access: access
                    )
                    return .none
                }

                return .run { send in
                    let requestedAccess = await musicProvider.requestAccess()
                    await send(
                        .providerRequestedAccessResponse(
                            requestID: requestID,
                            providerID: providerID,
                            access: requestedAccess
                        )
                    )
                }
                .cancellable(id: CancelID.providerAccess)

            case .providerRequestedAccessResponse(
                let requestID,
                let providerID,
                let access
            ):
                let expectedConnection = ProviderConnection.connecting(
                    providerID: providerID,
                    requestID: requestID
                )
                guard state.providerConnection == expectedConnection else {
                    return .none
                }
                resolveConnection(
                    state: &state,
                    providerID: providerID,
                    access: access
                )
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
                    state.providerConnection.access != nil
                else {
                    return .none
                }
                state.playbackTransition = .startingMusic(itemID)
                return .concatenate(
                    .send(.musicPlayback(.playbackStartAccepted)),
                    .run { send in
                        do {
                            try await musicProvider.play(itemID)
                            await send(.musicStartSucceeded(itemID))
                        } catch let error as MusicProviderError {
                            await send(.musicStartFailed(itemID, error))
                        } catch {
                            await send(.musicStartFailed(itemID, .playbackFailed))
                        }
                    }
                )

            case .musicPlayback:
                return .none

            case .musicStartSucceeded(let itemID):
                guard state.playbackTransition == .startingMusic(itemID) else {
                    return .none
                }
                state.playbackTransition = nil
                return .send(.musicPlayback(.transportFinished))

            case .musicStartFailed(let itemID, let error):
                guard state.playbackTransition == .startingMusic(itemID) else {
                    return .none
                }
                state.playbackTransition = nil
                return .send(.musicPlayback(.transportFailed(error)))

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none
            }
        }
    }

    private func beginAccessResolution(
        state: inout State,
        provider: ProviderDescriptor
    ) -> Effect<Action> {
        let providerChanged = state.providerConnection.providerID != provider.id
        let requestID = uuid()

        state.providerConnection = .connecting(
            providerID: provider.id,
            requestID: requestID
        )
        state.pendingProviderID = nil
        state.providerSwitchRequestID = nil

        if providerChanged {
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
        }

        return .run { send in
            let access = await musicProvider.currentAccess()
            await send(
                .providerCurrentAccessResponse(
                    requestID: requestID,
                    providerID: provider.id,
                    access: access
                )
            )
        }
        .cancellable(id: CancelID.providerAccess, cancelInFlight: true)
    }

    private func resolveConnection(
        state: inout State,
        providerID: ProviderID,
        access: MusicProviderAccess
    ) {
        switch access.authorization {
        case .authorized:
            state.providerConnection = .connected(
                providerID: providerID,
                access: access
            )
            state.search.playbackEligibility = access.playbackEligibility
        case .denied:
            state.providerConnection = .denied(providerID: providerID)
        case .restricted:
            state.providerConnection = .restricted(providerID: providerID)
        case .notDetermined:
            state.providerConnection = .failed(providerID: providerID)
        }
    }
}
