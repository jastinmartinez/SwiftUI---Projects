import ComposableArchitecture
import Foundation

/// Owns confirmed transport status and one pending status operation.
@Reducer
struct PlaybackSessionReducer {
    @ObservableState
    struct State: Equatable {
        var status: PlaybackStatus
        var pendingStatusChange: PendingStatusChange?
    }

    struct PendingStatusChange: Equatable, Sendable {
        let requestID: UUID
        let target: Target

        enum Target: Equatable, Sendable {
            case playing
            case paused
            case stopped
        }
    }

    enum Delegate: Equatable {
        case statusConfirmed
        case stopCompleted
        case transportFailed(PlaybackFailure)
    }

    enum Action: Equatable {
        case playPauseRequested
        case stopRequested
        case cancelPendingStatusChange
        case confirmedSnapshot(
            status: PlaybackStatus,
            position: TimeInterval
        )
        case statusCommandSucceeded(requestID: UUID)
        case statusCommandFailed(
            requestID: UUID,
            failure: PlaybackFailure
        )
        case delegate(Delegate)
    }

    private enum CancelID {
        case statusCommand
    }

    @Dependency(\.playbackTransport) var playbackTransport
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .playPauseRequested:
                guard state.pendingStatusChange == nil else {
                    return .none
                }

                let requestID = uuid()
                let target: PendingStatusChange.Target =
                    state.status == .playing ? .paused : .playing
                state.pendingStatusChange = PendingStatusChange(
                    requestID: requestID,
                    target: target
                )
                return .run { send in
                    do {
                        switch target {
                        case .playing:
                            try await playbackTransport.play()
                        case .paused:
                            try await playbackTransport.pause()
                        case .stopped:
                            return
                        }
                        try Task.checkCancellation()
                        await send(
                            .statusCommandSucceeded(
                                requestID: requestID
                            )
                        )
                    } catch is CancellationError {
                        return
                    } catch let failure as PlaybackFailure {
                        guard !Task.isCancelled else { return }
                        await send(
                            .statusCommandFailed(
                                requestID: requestID,
                                failure: failure
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .statusCommandFailed(
                                requestID: requestID,
                                failure: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.statusCommand,
                    cancelInFlight: true
                )

            case .stopRequested:
                guard state.pendingStatusChange == nil else {
                    return .none
                }

                let requestID = uuid()
                state.pendingStatusChange = PendingStatusChange(
                    requestID: requestID,
                    target: .stopped
                )
                return .run { send in
                    let outcome = await playbackTransport.stop()
                    guard !Task.isCancelled else { return }
                    switch outcome {
                    case .completed:
                        await send(
                            .statusCommandSucceeded(
                                requestID: requestID
                            )
                        )
                    case .interrupted:
                        await send(
                            .statusCommandFailed(
                                requestID: requestID,
                                failure: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.statusCommand,
                    cancelInFlight: true
                )

            case .cancelPendingStatusChange:
                state.pendingStatusChange = nil
                return .cancel(id: CancelID.statusCommand)

            case .confirmedSnapshot(let status, let position):
                let preservesStopped =
                    state.status == .stopped
                    && status == .paused
                    && position == 0
                if !preservesStopped {
                    state.status = status
                }

                guard let change = state.pendingStatusChange else {
                    return .none
                }
                let matchesTarget =
                    switch change.target {
                    case .playing:
                        status == .playing
                    case .paused:
                        status == .paused
                    case .stopped:
                        false
                    }
                guard matchesTarget else {
                    return .none
                }

                state.pendingStatusChange = nil
                return .concatenate(
                    .cancel(id: CancelID.statusCommand),
                    .send(.delegate(.statusConfirmed))
                )

            case .statusCommandSucceeded(let requestID):
                guard let change = state.pendingStatusChange,
                    change.requestID == requestID
                else {
                    return .none
                }
                guard change.target == .stopped else {
                    return .none
                }

                state.status = .stopped
                state.pendingStatusChange = nil
                return .send(.delegate(.stopCompleted))

            case .statusCommandFailed(let requestID, let failure):
                guard state.pendingStatusChange?.requestID == requestID else {
                    return .none
                }

                state.pendingStatusChange = nil
                return .send(.delegate(.transportFailed(failure)))

            case .delegate:
                return .none
            }
        }
    }
}
