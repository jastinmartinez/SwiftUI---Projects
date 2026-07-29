import ComposableArchitecture
import Foundation

/// Owns one transactional move from confirmed playback to a target track.
@Reducer
struct PlaybackTransitionFeature {
    @ObservableState
    struct State: Equatable {
        var phase: Phase
    }

    struct Intent: Equatable, Sendable {
        let queue: IdentifiedArrayOf<Track>
        let targetTrackID: TrackID
        let baselineTrackID: TrackID?
        let origin: Origin
    }

    enum Origin: Equatable, Sendable {
        case selection
        case navigation
    }

    struct Transaction: Equatable, Sendable {
        let requestID: UUID
        let intent: Intent

        var installation: PlaybackItemInstallation {
            PlaybackItemInstallation(id: requestID)
        }
    }

    struct Preparation: Equatable, Sendable {
        var stage: Stage
        var latestTargetSnapshot: PlaybackSnapshot?

        enum Stage: Equatable, Sendable {
            case resolving
            case loading
            case requestingPlayback
            case awaitingConfirmation
        }
    }

    enum Phase: Equatable, Sendable {
        case starting(Intent)
        case preparing(Transaction, Preparation)
        case committing(Transaction, Commit)
        case applyingConfirmation(Transaction, Commit)
        case rollingBack(Transaction, Rollback)
    }

    struct Commit: Equatable, Sendable {
        var snapshot: PlaybackSnapshot
        var followUp: FollowUp?
    }

    struct Rollback: Equatable, Sendable {
        let installation: PlaybackItemInstallation
        let reason: RollbackReason
        var followUp: FollowUp?
    }

    enum FollowUp: Equatable, Sendable {
        case transition(Intent)
        case stop
    }

    enum RollbackReason: Equatable, Sendable {
        case cancellation
        case supersession
        case failure(trackID: TrackID, failure: PlaybackFailure)
    }

    struct Confirmation: Equatable, Sendable {
        let intent: Intent
        let snapshot: PlaybackSnapshot
    }

    enum Completion: Equatable, Sendable {
        case confirmed
        case failed(trackID: TrackID, failure: PlaybackFailure)
        case cancelled
        case stopReady
    }

    enum Delegate: Equatable {
        case confirmedSnapshotReady(PlaybackSnapshot)
        case confirmedPlaybackFailed(
            trackID: TrackID?,
            failure: PlaybackFailure
        )
        case confirmationReady(Confirmation)
        case completed(Completion)
    }

    enum Action: Equatable {
        case start
        case supersede(Intent)
        case cancel
        case stopRequested
        case snapshotReceived(PlaybackSnapshot)
        case cachedSnapshotReplayRequested(
            requestID: UUID,
            snapshot: PlaybackSnapshot
        )
        case runtimeFailureReceived(TrackID?, PlaybackFailure)
        case resourceResolved(
            requestID: UUID,
            resource: PlaybackResource
        )
        case resourceResolutionFailed(
            requestID: UUID,
            failure: PlaybackFailure
        )
        case itemLoaded(requestID: UUID)
        case itemLoadFailed(
            requestID: UUID,
            failure: PlaybackFailure
        )
        case playbackRequested(requestID: UUID)
        case playbackRequestFailed(
            requestID: UUID,
            failure: PlaybackFailure
        )
        case commitCompleted(requestID: UUID)
        case rollbackCompleted(requestID: UUID)
        case confirmationApplied
        case delegate(Delegate)
    }

    private enum CancelID {
        case transition
    }

    @Dependency(\.playbackResourceClients) var playbackResourceClients
    @Dependency(\.playbackItem) var playbackItem
    @Dependency(\.playbackTransport) var playbackTransport
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                guard case .starting(let intent) = state.phase else {
                    return .none
                }

                let transaction = Transaction(
                    requestID: uuid(),
                    intent: intent
                )
                state.phase = .preparing(
                    transaction,
                    Preparation(
                        stage: .resolving,
                        latestTargetSnapshot: nil
                    )
                )

                guard
                    let resourceClient =
                        playbackResourceClients[
                            intent.targetTrackID.providerID
                        ]
                else {
                    return .send(
                        .resourceResolutionFailed(
                            requestID: transaction.requestID,
                            failure: .resourceUnavailable
                        )
                    )
                }

                return .run { send in
                    do {
                        let resource = try await resourceClient.resolve(
                            intent.targetTrackID
                        )
                        try Task.checkCancellation()
                        await send(
                            .resourceResolved(
                                requestID: transaction.requestID,
                                resource: resource
                            )
                        )
                    } catch is CancellationError {
                        return
                    } catch let failure as PlaybackFailure {
                        guard !Task.isCancelled else { return }
                        await send(
                            .resourceResolutionFailed(
                                requestID: transaction.requestID,
                                failure: failure
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .resourceResolutionFailed(
                                requestID: transaction.requestID,
                                failure: .resourceUnavailable
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.transition,
                    cancelInFlight: true
                )

            case .resourceResolved(let requestID, let resource):
                guard
                    case .preparing(
                        let transaction,
                        var preparation
                    ) = state.phase,
                    transaction.requestID == requestID,
                    transaction.intent.targetTrackID == resource.trackID,
                    preparation.stage == .resolving
                else {
                    return .none
                }

                preparation.stage = .loading
                state.phase = .preparing(transaction, preparation)
                return .run { send in
                    do {
                        try await playbackItem.load(
                            resource,
                            transaction.installation
                        )
                        try Task.checkCancellation()
                        await send(
                            .itemLoaded(requestID: transaction.requestID)
                        )
                    } catch is CancellationError {
                        return
                    } catch let failure as PlaybackFailure {
                        guard !Task.isCancelled else { return }
                        await send(
                            .itemLoadFailed(
                                requestID: transaction.requestID,
                                failure: failure
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .itemLoadFailed(
                                requestID: transaction.requestID,
                                failure: .preparationFailed
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.transition,
                    cancelInFlight: true
                )

            case .itemLoaded(let requestID):
                guard
                    case .preparing(
                        let transaction,
                        var preparation
                    ) = state.phase,
                    transaction.requestID == requestID,
                    preparation.stage == .loading
                else {
                    return .none
                }

                preparation.stage = .requestingPlayback
                state.phase = .preparing(transaction, preparation)
                return .run { send in
                    do {
                        try await playbackTransport.play()
                        try Task.checkCancellation()
                        await send(
                            .playbackRequested(
                                requestID: transaction.requestID
                            )
                        )
                    } catch is CancellationError {
                        return
                    } catch let failure as PlaybackFailure {
                        guard !Task.isCancelled else { return }
                        await send(
                            .playbackRequestFailed(
                                requestID: transaction.requestID,
                                failure: failure
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .playbackRequestFailed(
                                requestID: transaction.requestID,
                                failure: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.transition,
                    cancelInFlight: true
                )

            case .playbackRequested(let requestID):
                guard
                    case .preparing(
                        let transaction,
                        var preparation
                    ) = state.phase,
                    transaction.requestID == requestID,
                    preparation.stage == .requestingPlayback
                else {
                    return .none
                }

                preparation.stage = .awaitingConfirmation
                state.phase = .preparing(transaction, preparation)
                return preparation.latestTargetSnapshot.map {
                    .send(
                        .cachedSnapshotReplayRequested(
                            requestID: requestID,
                            snapshot: $0
                        )
                    )
                } ?? .none

            case .snapshotReceived(let snapshot):
                guard
                    case .preparing(
                        let transaction,
                        var preparation
                    ) = state.phase
                else {
                    return .none
                }

                if snapshot.currentTrackID
                    == transaction.intent.targetTrackID
                {
                    preparation.latestTargetSnapshot = snapshot
                    state.phase = .preparing(transaction, preparation)
                    return .none
                }
                if snapshot.currentTrackID
                    == transaction.intent.baselineTrackID
                {
                    return .send(
                        .delegate(.confirmedSnapshotReady(snapshot))
                    )
                }
                return .none

            case .cachedSnapshotReplayRequested(
                let requestID,
                let snapshot
            ):
                guard
                    case .preparing(
                        let transaction,
                        let preparation
                    ) = state.phase,
                    transaction.requestID == requestID,
                    preparation.stage == .awaitingConfirmation,
                    preparation.latestTargetSnapshot == snapshot
                else {
                    return .none
                }
                return .none

            case .resourceResolutionFailed(
                let requestID,
                let failure
            ):
                guard
                    case .preparing(
                        let transaction,
                        let preparation
                    ) = state.phase,
                    transaction.requestID == requestID,
                    preparation.stage == .resolving
                else {
                    return .none
                }
                return .send(
                    .delegate(
                        .completed(
                            .failed(
                                trackID:
                                    transaction.intent.targetTrackID,
                                failure: failure
                            )
                        )
                    )
                )

            case .itemLoadFailed(let requestID, let failure):
                guard
                    case .preparing(
                        let transaction,
                        let preparation
                    ) = state.phase,
                    transaction.requestID == requestID,
                    preparation.stage == .loading
                else {
                    return .none
                }
                return .send(
                    .delegate(
                        .completed(
                            .failed(
                                trackID:
                                    transaction.intent.targetTrackID,
                                failure: failure
                            )
                        )
                    )
                )

            case .supersede,
                .cancel,
                .stopRequested,
                .runtimeFailureReceived,
                .playbackRequestFailed,
                .commitCompleted,
                .rollbackCompleted,
                .confirmationApplied,
                .delegate:
                return .none
            }
        }
    }
}
