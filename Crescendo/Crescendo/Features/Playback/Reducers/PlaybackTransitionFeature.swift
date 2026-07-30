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
        let target: Track
        let baselineTrackID: TrackID?

        var targetTrackID: TrackID {
            target.id
        }
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
        case rollbackRequested(requestID: UUID)
        case rollbackCompleted(requestID: UUID)
        case confirmationApplied
        case delegate(Delegate)
    }

    private enum CancelID {
        case transition
    }

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
                        stage: .loading,
                        latestTargetSnapshot: nil
                    )
                )

                return .run { send in
                    do {
                        try await playbackItem.load(
                            intent.target.id,
                            intent.target.playbackURL,
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
                switch state.phase {
                case .preparing(
                    let transaction,
                    var preparation
                ):
                    let intent = transaction.intent
                    let observedTrackID = snapshot.currentTrackID
                    let targetTrackID = intent.targetTrackID

                    if observedTrackID == targetTrackID {
                        if preparation.stage == .awaitingConfirmation {
                            state.phase = .committing(
                                transaction,
                                Commit(snapshot: snapshot, followUp: nil)
                            )
                            return .run { send in
                                await playbackItem.commit(
                                    transaction.installation
                                )
                                guard !Task.isCancelled else { return }
                                await send(
                                    .commitCompleted(
                                        requestID: transaction.requestID
                                    )
                                )
                            }
                            .cancellable(
                                id: CancelID.transition,
                                cancelInFlight: true
                            )
                        }

                        preparation.latestTargetSnapshot = snapshot
                        state.phase = .preparing(
                            transaction,
                            preparation
                        )
                        return .none
                    }

                    let baselineTrackID = intent.baselineTrackID
                    if observedTrackID == baselineTrackID {
                        return .send(
                            .delegate(
                                .confirmedSnapshotReady(snapshot)
                            )
                        )
                    }

                    return .none

                case .committing(let transaction, var commit):
                    let targetTrackID = transaction.intent.targetTrackID
                    guard snapshot.currentTrackID == targetTrackID else {
                        return .none
                    }
                    commit.snapshot = snapshot
                    state.phase = .committing(transaction, commit)
                    return .none

                case .applyingConfirmation(
                    let transaction,
                    var commit
                ):
                    let targetTrackID = transaction.intent.targetTrackID
                    guard snapshot.currentTrackID == targetTrackID else {
                        return .none
                    }
                    commit.snapshot = snapshot
                    state.phase = .applyingConfirmation(
                        transaction,
                        commit
                    )
                    return .none

                case .rollingBack(let transaction, _):
                    let intent = transaction.intent
                    let baselineTrackID = intent.baselineTrackID
                    guard snapshot.currentTrackID == baselineTrackID else {
                        return .none
                    }
                    return .send(
                        .delegate(.confirmedSnapshotReady(snapshot))
                    )

                case .starting:
                    return .none
                }

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
                state.phase = .committing(
                    transaction,
                    Commit(snapshot: snapshot, followUp: nil)
                )
                return .run { send in
                    await playbackItem.commit(transaction.installation)
                    guard !Task.isCancelled else { return }
                    await send(
                        .commitCompleted(
                            requestID: transaction.requestID
                        )
                    )
                }
                .cancellable(
                    id: CancelID.transition,
                    cancelInFlight: true
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
                let targetTrackID =
                    transaction.intent.targetTrackID
                state.phase = .rollingBack(
                    transaction,
                    Rollback(
                        installation: transaction.installation,
                        reason: .failure(
                            trackID: targetTrackID,
                            failure: failure
                        ),
                        followUp: nil
                    )
                )
                return .send(
                    .rollbackRequested(requestID: transaction.requestID)
                )

            case .playbackRequestFailed(
                let requestID,
                let failure
            ):
                switch state.phase {
                case .preparing(
                    let transaction,
                    let preparation
                ):
                    guard
                        transaction.requestID == requestID,
                        preparation.stage == .requestingPlayback
                            || preparation.stage == .awaitingConfirmation
                    else {
                        return .none
                    }
                    let targetTrackID =
                        transaction.intent.targetTrackID
                    state.phase = .rollingBack(
                        transaction,
                        Rollback(
                            installation: transaction.installation,
                            reason: .failure(
                                trackID: targetTrackID,
                                failure: failure
                            ),
                            followUp: nil
                        )
                    )
                    return .send(
                        .rollbackRequested(
                            requestID: transaction.requestID
                        )
                    )

                case .committing(let transaction, _),
                    .applyingConfirmation(let transaction, _):
                    guard transaction.requestID == requestID else {
                        return .none
                    }
                    let targetTrackID =
                        transaction.intent.targetTrackID
                    return .send(
                        .delegate(
                            .confirmedPlaybackFailed(
                                trackID: targetTrackID,
                                failure: failure
                            )
                        )
                    )

                case .starting, .rollingBack:
                    return .none
                }

            case .commitCompleted(let requestID):
                guard
                    case .committing(
                        let transaction,
                        let commit
                    ) = state.phase,
                    transaction.requestID == requestID
                else {
                    return .none
                }
                state.phase = .applyingConfirmation(
                    transaction,
                    commit
                )
                return .send(
                    .delegate(
                        .confirmationReady(
                            Confirmation(
                                intent: transaction.intent,
                                snapshot: commit.snapshot
                            )
                        )
                    )
                )

            case .confirmationApplied:
                guard
                    case .applyingConfirmation(
                        _,
                        let commit
                    ) = state.phase
                else {
                    return .none
                }

                switch commit.followUp {
                case .none:
                    return .send(.delegate(.completed(.confirmed)))

                case .transition(let intent):
                    let rebasedIntent = Intent(
                        target: intent.target,
                        baselineTrackID: commit.snapshot.currentTrackID
                    )
                    state.phase = .starting(rebasedIntent)
                    return .send(.start)

                case .stop:
                    return .send(.delegate(.completed(.stopReady)))
                }

            case .rollbackRequested(let requestID):
                guard
                    case .rollingBack(let transaction, _) = state.phase,
                    transaction.requestID == requestID
                else {
                    return .none
                }
                let installation = transaction.installation
                return .concatenate(
                    .cancel(id: CancelID.transition),
                    .run { send in
                        await playbackItem.rollback(installation)
                        guard !Task.isCancelled else { return }
                        await send(
                            .rollbackCompleted(requestID: requestID)
                        )
                    }
                    .cancellable(
                        id: CancelID.transition,
                        cancelInFlight: true
                    )
                )

            case .rollbackCompleted(let requestID):
                guard
                    case .rollingBack(
                        let transaction,
                        let rollback
                    ) = state.phase,
                    transaction.requestID == requestID
                else {
                    return .none
                }

                switch rollback.followUp {
                case .transition(let intent):
                    state.phase = .starting(intent)
                    return .send(.start)

                case .stop:
                    return .send(.delegate(.completed(.stopReady)))

                case .none:
                    switch rollback.reason {
                    case .cancellation, .supersession:
                        return .send(
                            .delegate(.completed(.cancelled))
                        )

                    case .failure(let trackID, let failure):
                        return .send(
                            .delegate(
                                .completed(
                                    .failed(
                                        trackID: trackID,
                                        failure: failure
                                    )
                                )
                            )
                        )
                    }
                }

            case .supersede(let intent):
                switch state.phase {
                case .starting:
                    state.phase = .starting(intent)
                    return .concatenate(
                        .cancel(id: CancelID.transition),
                        .send(.start)
                    )

                case .preparing(
                    let transaction,
                    _
                ):
                    state.phase = .rollingBack(
                        transaction,
                        Rollback(
                            installation: transaction.installation,
                            reason: .supersession,
                            followUp: .transition(intent)
                        )
                    )
                    return .send(
                        .rollbackRequested(
                            requestID: transaction.requestID
                        )
                    )

                case .committing(let transaction, var commit):
                    commit.followUp = .transition(intent)
                    state.phase = .committing(transaction, commit)
                    return .none

                case .applyingConfirmation(
                    let transaction,
                    var commit
                ):
                    commit.followUp = .transition(intent)
                    state.phase = .applyingConfirmation(
                        transaction,
                        commit
                    )
                    return .none

                case .rollingBack(
                    let transaction,
                    var rollback
                ):
                    rollback.followUp = .transition(intent)
                    state.phase = .rollingBack(
                        transaction,
                        rollback
                    )
                    return .none
                }

            case .cancel:
                switch state.phase {
                case .starting:
                    return .concatenate(
                        .cancel(id: CancelID.transition),
                        .send(.delegate(.completed(.cancelled)))
                    )

                case .preparing(
                    let transaction,
                    _
                ):
                    state.phase = .rollingBack(
                        transaction,
                        Rollback(
                            installation: transaction.installation,
                            reason: .cancellation,
                            followUp: nil
                        )
                    )
                    return .send(
                        .rollbackRequested(
                            requestID: transaction.requestID
                        )
                    )

                case .committing(let transaction, var commit):
                    commit.followUp = nil
                    state.phase = .committing(transaction, commit)
                    return .none

                case .applyingConfirmation(
                    let transaction,
                    var commit
                ):
                    commit.followUp = nil
                    state.phase = .applyingConfirmation(
                        transaction,
                        commit
                    )
                    return .none

                case .rollingBack(
                    let transaction,
                    let rollback
                ):
                    state.phase = .rollingBack(
                        transaction,
                        Rollback(
                            installation: rollback.installation,
                            reason: .cancellation,
                            followUp: nil
                        )
                    )
                    return .none
                }

            case .stopRequested:
                switch state.phase {
                case .starting:
                    return .concatenate(
                        .cancel(id: CancelID.transition),
                        .send(.delegate(.completed(.stopReady)))
                    )

                case .preparing(
                    let transaction,
                    _
                ):
                    state.phase = .rollingBack(
                        transaction,
                        Rollback(
                            installation: transaction.installation,
                            reason: .cancellation,
                            followUp: .stop
                        )
                    )
                    return .send(
                        .rollbackRequested(
                            requestID: transaction.requestID
                        )
                    )

                case .committing(let transaction, var commit):
                    commit.followUp = .stop
                    state.phase = .committing(transaction, commit)
                    return .none

                case .applyingConfirmation(
                    let transaction,
                    var commit
                ):
                    commit.followUp = .stop
                    state.phase = .applyingConfirmation(
                        transaction,
                        commit
                    )
                    return .none

                case .rollingBack(
                    let transaction,
                    var rollback
                ):
                    rollback.followUp = .stop
                    state.phase = .rollingBack(
                        transaction,
                        rollback
                    )
                    return .none
                }

            case .runtimeFailureReceived(let trackID, let failure):
                switch state.phase {
                case .starting(let intent):
                    if trackID == intent.targetTrackID {
                        return .send(
                            .delegate(
                                .completed(
                                    .failed(
                                        trackID: intent.targetTrackID,
                                        failure: failure
                                    )
                                )
                            )
                        )
                    }
                    guard trackID == intent.baselineTrackID else {
                        return .none
                    }
                    return .send(
                        .delegate(
                            .confirmedPlaybackFailed(
                                trackID: trackID,
                                failure: failure
                            )
                        )
                    )

                case .preparing(let transaction, _),
                    .committing(let transaction, _):
                    let intent = transaction.intent
                    let targetTrackID = intent.targetTrackID
                    if trackID == targetTrackID {
                        let installation = transaction.installation
                        state.phase = .rollingBack(
                            transaction,
                            Rollback(
                                installation: installation,
                                reason: .failure(
                                    trackID: targetTrackID,
                                    failure: failure
                                ),
                                followUp: nil
                            )
                        )
                        return .send(
                            .rollbackRequested(
                                requestID: transaction.requestID
                            )
                        )
                    }
                    let baselineTrackID = intent.baselineTrackID
                    guard trackID == baselineTrackID else {
                        return .none
                    }
                    return .send(
                        .delegate(
                            .confirmedPlaybackFailed(
                                trackID: trackID,
                                failure: failure
                            )
                        )
                    )

                case .applyingConfirmation(let transaction, _):
                    let intent = transaction.intent
                    let targetTrackID = intent.targetTrackID
                    let baselineTrackID = intent.baselineTrackID
                    let isConfirmedIdentity =
                        trackID == targetTrackID
                        || trackID == baselineTrackID
                    guard isConfirmedIdentity else {
                        return .none
                    }
                    return .send(
                        .delegate(
                            .confirmedPlaybackFailed(
                                trackID: trackID,
                                failure: failure
                            )
                        )
                    )

                case .rollingBack(let transaction, _):
                    let intent = transaction.intent
                    let baselineTrackID = intent.baselineTrackID
                    guard trackID == baselineTrackID else {
                        return .none
                    }
                    return .send(
                        .delegate(
                            .confirmedPlaybackFailed(
                                trackID: trackID,
                                failure: failure
                            )
                        )
                    )
                }

            case .delegate:
                return .none
            }
        }
    }
}

extension PlaybackTransitionFeature.State {
    /// Reports whether the transition can accept a new Stop request.
    ///
    /// A transition stops accepting Stop after it has retained one as its
    /// follow-up operation.
    var acceptsStopRequest: Bool {
        switch phase {
        case .starting, .preparing:
            return true
        case .committing(_, let commit),
            .applyingConfirmation(_, let commit):
            return commit.followUp != .stop
        case .rollingBack(_, let rollback):
            return rollback.followUp != .stop
        }
    }
}
