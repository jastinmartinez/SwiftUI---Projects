import ComposableArchitecture
import Foundation

/// Owns confirmed playback state and coordinates playback-domain workflows.
@Reducer
struct PlaybackFeature {
    @ObservableState
    struct State: Equatable {
        var queue: PlaybackQueueFeature.State
        var status: PlaybackStatus
        var failureNotice: PlaybackFailureNotice?
        var timeline: PlaybackTimelineFeature.State
        var pendingPlaybackTransition: PendingPlaybackTransition?
        var pendingStatusChange: PendingStatusChange?
        var isPlayerPresented: Bool
    }

    struct PendingStatusChange: Equatable {
        let requestID: UUID
        let target: Target

        enum Target: Equatable {
            case playing
            case paused
            case stopped
        }
    }

    enum Action: Equatable {
        case task
        case selectionReceived(
            TrackID,
            loadedResults: IdentifiedArrayOf<Track>
        )
        case resolveTransition(requestID: UUID, trackID: TrackID)
        case transitionResourceResolved(
            requestID: UUID,
            resource: PlaybackResource
        )
        case transitionResolutionFailed(
            requestID: UUID,
            failure: PlaybackFailure
        )
        case loadTransition(requestID: UUID, resource: PlaybackResource)
        case transitionItemLoaded(requestID: UUID)
        case transitionItemLoadFailed(
            requestID: UUID,
            failure: PlaybackFailure
        )
        case playTransition(requestID: UUID)
        case transitionPlayRequested(requestID: UUID)
        case transitionPlayFailed(
            requestID: UUID,
            trackID: TrackID,
            failure: PlaybackFailure
        )
        case transitionCommitCompleted(
            requestID: UUID,
            installation: PlaybackItemInstallation
        )
        case transitionConfirmationApplied(
            requestID: UUID,
            installation: PlaybackItemInstallation
        )
        case transitionRollbackCompleted(requestID: UUID)
        case cancelPlaybackTransition
        case playPauseTapped
        case stopTapped
        case performStatusChange(
            requestID: UUID,
            target: PendingStatusChange.Target
        )
        case statusChangeSucceeded(requestID: UUID)
        case statusChangeFailed(
            requestID: UUID,
            error: MusicProviderError
        )
        case previousTapped
        case nextTapped
        case repeatTapped
        case shuffleTapped
        case setPlayerPresented(Bool)
        case observationReceived(PlaybackObservation)
        case reconcileSnapshot(PlaybackSnapshot)
        case replayTransitionSnapshot(
            requestID: UUID,
            snapshot: PlaybackSnapshot
        )
        case currentTrackCompleted(TrackID)
        case runtimePlaybackFailed(TrackID?, PlaybackFailure)
        case timelinePositionChanged(TimeInterval)
        case timelineInteractionEnded
        case restartTapped
        case seekBackwardTapped
        case seekForwardTapped
        case queue(PlaybackQueueFeature.Action)
        case timeline(PlaybackTimelineFeature.Action)
    }

    private enum CancelID {
        case playbackObservation
        case playbackTransition
        case statusChange
    }

    @Dependency(\.playbackResourceClients) var playbackResourceClients
    @Dependency(\.playbackItem) var playbackItem
    @Dependency(\.playbackTransport) var playbackTransport
    @Dependency(\.playbackTimeline) var playbackTimeline
    @Dependency(\.playbackObservation) var playbackObservation
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Scope(state: \.queue, action: \.queue) {
            PlaybackQueueFeature()
        }
        Scope(state: \.timeline, action: \.timeline) {
            PlaybackTimelineFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    let observations =
                        await playbackObservation.observations()
                    for await observation in observations {
                        await send(.observationReceived(observation))
                    }
                }
                .cancellable(
                    id: CancelID.playbackObservation,
                    cancelInFlight: true
                )

            case .selectionReceived(let trackID, let loadedResults):
                let hasNowPlaying = !state.queue.tracks.isEmpty
                guard loadedResults[id: trackID] != nil else {
                    return .none
                }

                if !hasNowPlaying {
                    state.isPlayerPresented = true
                }
                let requestID = uuid()
                let intent = PendingPlaybackTransition.TransitionIntent(
                    requestID: requestID,
                    queue: loadedResults,
                    targetTrackID: trackID,
                    origin: .selection
                )
                if state.pendingPlaybackTransition?
                    .retainLatestFollowUp(.transition(intent)) == true
                {
                    state.failureNotice = nil
                    state.pendingStatusChange = nil
                    return .cancel(id: CancelID.statusChange)
                }

                let rollbackInstallation =
                    state.pendingPlaybackTransition?.rollbackInstallation
                state.pendingPlaybackTransition = PendingPlaybackTransition(
                    requestID: requestID,
                    queue: loadedResults,
                    targetTrackID: trackID,
                    origin: .selection,
                    settlement: rollbackInstallation.map {
                        .rollingBack(.superseding($0))
                    } ?? .none
                )
                state.failureNotice = nil
                // A newer selection supersedes an older transport request.
                state.pendingStatusChange = nil
                let transitionEffect: Effect<Action>
                if let rollbackInstallation {
                    transitionEffect = .concatenate(
                        .cancel(id: CancelID.playbackTransition),
                        rollbackEffect(
                            rollbackInstallation,
                            requestID: requestID
                        )
                    )
                } else {
                    transitionEffect = .send(
                        .resolveTransition(
                            requestID: requestID,
                            trackID: trackID
                        )
                    )
                }
                return .concatenate(
                    .cancel(id: CancelID.statusChange),
                    transitionEffect
                )

            case .resolveTransition(let requestID, let trackID):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.targetTrackID == trackID,
                    pending.canAdvance
                else { return .none }

                let resourceClient = playbackResourceClients[trackID.providerID]
                return .run { send in
                    guard let resourceClient else {
                        await send(
                            .transitionResolutionFailed(
                                requestID: requestID,
                                failure: .resourceUnavailable
                            )
                        )
                        return
                    }
                    do {
                        let resource = try await resourceClient.resolve(trackID)
                        try Task.checkCancellation()
                        await send(
                            .transitionResourceResolved(
                                requestID: requestID,
                                resource: resource
                            )
                        )
                    } catch is CancellationError {
                        return
                    } catch let failure as PlaybackFailure {
                        guard !Task.isCancelled else { return }
                        await send(
                            .transitionResolutionFailed(
                                requestID: requestID,
                                failure: failure
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .transitionResolutionFailed(
                                requestID: requestID,
                                failure: .resourceUnavailable
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.playbackTransition,
                    cancelInFlight: true
                )

            case .transitionResourceResolved(let requestID, let resource):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.targetTrackID == resource.trackID,
                    pending.canAdvance
                else { return .none }
                return .send(
                    .loadTransition(requestID: requestID, resource: resource)
                )

            case .loadTransition(let requestID, let resource):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.targetTrackID == resource.trackID,
                    pending.canAdvance
                else { return .none }
                let installation = PlaybackItemInstallation(id: requestID)
                return .run { send in
                    do {
                        try await playbackItem.load(resource, installation)
                        try Task.checkCancellation()
                        await send(.transitionItemLoaded(requestID: requestID))
                    } catch is CancellationError {
                        await playbackItem.rollback(installation)
                        return
                    } catch let failure as PlaybackFailure {
                        guard !Task.isCancelled else { return }
                        await send(
                            .transitionItemLoadFailed(
                                requestID: requestID,
                                failure: failure
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .transitionItemLoadFailed(
                                requestID: requestID,
                                failure: .preparationFailed
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.playbackTransition,
                    cancelInFlight: true
                )

            case .transitionItemLoaded(let requestID):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.canAdvance,
                    case .awaitingLoad(let latestTargetSnapshot) =
                        pending.confirmationReadiness
                else { return .none }
                state.pendingPlaybackTransition?.confirmationReadiness =
                    .awaitingPlay(
                        latestTargetSnapshot: latestTargetSnapshot
                    )
                return .send(.playTransition(requestID: requestID))

            case .playTransition(let requestID):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.canAdvance,
                    case .awaitingPlay =
                        pending.confirmationReadiness
                else { return .none }
                let trackID = pending.targetTrackID
                let installation = PlaybackItemInstallation(id: requestID)
                return .run { send in
                    do {
                        try await playbackTransport.play()
                        try Task.checkCancellation()
                        await send(
                            .transitionPlayRequested(requestID: requestID)
                        )
                    } catch is CancellationError {
                        await playbackItem.rollback(installation)
                        return
                    } catch let failure as PlaybackFailure {
                        guard !Task.isCancelled else { return }
                        await send(
                            .transitionPlayFailed(
                                requestID: requestID,
                                trackID: trackID,
                                failure: failure
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .transitionPlayFailed(
                                requestID: requestID,
                                trackID: trackID,
                                failure: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.playbackTransition,
                    cancelInFlight: true
                )

            case .transitionPlayRequested(let requestID):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.canAdvance,
                    case .awaitingPlay(let latestTargetSnapshot) =
                        pending.confirmationReadiness
                else { return .none }
                // Successful command return opens identity confirmation; the
                // observation still supplies all confirmed playback truth.
                state.pendingPlaybackTransition?.confirmationReadiness =
                    .readyForConfirmation
                return latestTargetSnapshot.map {
                    .send(
                        .replayTransitionSnapshot(
                            requestID: requestID,
                            snapshot: $0
                        )
                    )
                } ?? .none

            case .transitionCommitCompleted(
                let requestID,
                let installation
            ):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.installation == installation,
                    case .committing(let commit) = pending.settlement
                else { return .none }

                let snapshot = commit.snapshot
                applyConfirmedSnapshotState(snapshot, to: &state)
                state.pendingPlaybackTransition?.settlement =
                    .applyingCommit(commit)

                let queueEffect: Effect<Action>
                switch pending.origin {
                case .selection:
                    queueEffect = .send(
                        .queue(
                            .replace(
                                pending.queue,
                                startingAt: pending.targetTrackID
                            )
                        )
                    )
                case .navigation:
                    queueEffect = .send(
                        .queue(
                            .currentTrackConfirmed(pending.targetTrackID)
                        )
                    )
                }
                return .concatenate(
                    queueEffect,
                    .send(
                        .timeline(
                            .positionObserved(snapshot.position)
                        )
                    ),
                    .send(
                        .transitionConfirmationApplied(
                            requestID: requestID,
                            installation: installation
                        )
                    )
                )

            case .transitionConfirmationApplied(
                let requestID,
                let installation
            ):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.installation == installation,
                    case .applyingCommit(let commit) = pending.settlement
                else { return .none }

                applyConfirmedSnapshotState(commit.snapshot, to: &state)
                state.timeline.confirmedPosition = max(
                    commit.snapshot.position,
                    0
                )
                switch commit.followUp {
                case .transition(let intent):
                    state.pendingPlaybackTransition =
                        PendingPlaybackTransition(
                            requestID: intent.requestID,
                            queue: intent.queue,
                            targetTrackID: intent.targetTrackID,
                            origin: intent.origin
                        )
                    return .send(
                        .resolveTransition(
                            requestID: intent.requestID,
                            trackID: intent.targetTrackID
                        )
                    )
                case .stop(let stopRequestID):
                    state.pendingPlaybackTransition = nil
                    return .send(
                        .performStatusChange(
                            requestID: stopRequestID,
                            target: .stopped
                        )
                    )
                case nil:
                    state.pendingPlaybackTransition = nil
                    return .none
                }

            case .transitionRollbackCompleted(let requestID):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    case .rollingBack(let rollback) = pending.settlement
                else { return .none }

                switch rollback {
                case .superseding:
                    state.pendingPlaybackTransition?.settlement = .none
                    return .send(
                        .resolveTransition(
                            requestID: requestID,
                            trackID: pending.targetTrackID
                        )
                    )
                case .abandoning(_, followUp: .none):
                    state.pendingPlaybackTransition = nil
                    return .none
                case .abandoning(_, followUp: .stop(let stopRequestID)):
                    state.pendingPlaybackTransition = nil
                    return .send(
                        .performStatusChange(
                            requestID: stopRequestID,
                            target: .stopped
                        )
                    )
                }

            case .transitionResolutionFailed(let requestID, let failure),
                .transitionItemLoadFailed(let requestID, let failure):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.canAdvance
                else { return .none }

                state.failureNotice = PlaybackFailureNotice(
                    trackID: pending.targetTrackID,
                    failure: failure
                )
                state.pendingPlaybackTransition = nil
                return .none

            case .transitionPlayFailed(let requestID, let trackID, let failure):
                if let pending = state.pendingPlaybackTransition {
                    guard pending.requestID == requestID,
                        pending.targetTrackID == trackID
                    else { return .none }
                    state.failureNotice = PlaybackFailureNotice(
                        trackID: trackID,
                        failure: failure
                    )
                    switch pending.settlement {
                    case .committing, .applyingCommit:
                        return .none
                    case .rollingBack:
                        return .none
                    case .none:
                        let installation = pending.installation
                        state.pendingPlaybackTransition?
                            .discardPendingTargetSnapshot()
                        state.pendingPlaybackTransition?.settlement =
                            .rollingBack(
                                .abandoning(
                                    installation,
                                    followUp: .none
                                )
                            )
                        return rollbackEffect(
                            installation,
                            requestID: requestID
                        )
                    }
                } else {
                    guard state.queue.currentTrackID == trackID else {
                        return .none
                    }
                }

                state.failureNotice = PlaybackFailureNotice(
                    trackID: trackID,
                    failure: failure
                )
                return .none

            case .cancelPlaybackTransition:
                guard let pending = state.pendingPlaybackTransition else {
                    return .cancel(id: CancelID.playbackTransition)
                }
                switch pending.settlement {
                case .committing(var commit):
                    commit.followUp = nil
                    state.pendingPlaybackTransition?.settlement =
                        .committing(commit)
                    return .none
                case .applyingCommit(var commit):
                    commit.followUp = nil
                    state.pendingPlaybackTransition?.settlement =
                        .applyingCommit(commit)
                    return .none
                case .none, .rollingBack:
                    break
                }
                let installation = pending.rollbackInstallation
                state.pendingPlaybackTransition?
                    .discardPendingTargetSnapshot()
                state.pendingPlaybackTransition?.settlement =
                    .rollingBack(
                        .abandoning(
                            installation,
                            followUp: .none
                        )
                    )
                return .concatenate(
                    .cancel(id: CancelID.playbackTransition),
                    rollbackEffect(
                        installation,
                        requestID: pending.requestID
                    )
                )

            case .playPauseTapped:
                guard state.canRequestPlayPause else { return .none }
                let target: PendingStatusChange.Target =
                    state.status == .playing ? .paused : .playing
                let requestID = uuid()
                state.pendingStatusChange = PendingStatusChange(
                    requestID: requestID,
                    target: target
                )
                state.failureNotice = nil
                return .send(
                    .performStatusChange(
                        requestID: requestID,
                        target: target
                    )
                )

            case .stopTapped:
                guard state.canRequestStop else { return .none }
                let requestID = uuid()
                state.pendingStatusChange = PendingStatusChange(
                    requestID: requestID,
                    target: .stopped
                )
                state.failureNotice = nil
                // Stopping abandons the track that is about to play.
                if state.pendingPlaybackTransition?
                    .retainLatestFollowUp(
                        .stop(requestID: requestID)
                    ) == true
                {
                    return .none
                }
                if let pending = state.pendingPlaybackTransition {
                    let installation = pending.rollbackInstallation
                    state.pendingPlaybackTransition?
                        .discardPendingTargetSnapshot()
                    state.pendingPlaybackTransition?.settlement =
                        .rollingBack(
                            .abandoning(
                                installation,
                                followUp: .stop(requestID: requestID)
                            )
                        )
                    return .concatenate(
                        .cancel(id: CancelID.playbackTransition),
                        rollbackEffect(
                            installation,
                            requestID: pending.requestID
                        )
                    )
                }
                return .concatenate(
                    .cancel(id: CancelID.playbackTransition),
                    .send(
                        .performStatusChange(
                            requestID: requestID,
                            target: .stopped
                        )
                    )
                )

            case .performStatusChange(let requestID, let target):
                guard let change = state.pendingStatusChange,
                    change.requestID == requestID,
                    change.target == target
                else { return .none }
                return .run { send in
                    do {
                        switch target {
                        case .playing:
                            try await playbackTransport.play()
                        case .paused:
                            try await playbackTransport.pause()
                        case .stopped:
                            let outcome = await playbackTransport.stop()
                            guard !Task.isCancelled else { return }
                            guard outcome == .completed else {
                                await send(
                                    .statusChangeFailed(
                                        requestID: requestID,
                                        error: .playbackFailed
                                    )
                                )
                                return
                            }
                        }
                        try Task.checkCancellation()
                        await send(.statusChangeSucceeded(requestID: requestID))
                    } catch is CancellationError {
                        return
                    } catch let error as MusicProviderError {
                        guard !Task.isCancelled else { return }
                        await send(
                            .statusChangeFailed(
                                requestID: requestID,
                                error: error
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .statusChangeFailed(
                                requestID: requestID,
                                error: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.statusChange,
                    cancelInFlight: true
                )

            case .statusChangeSucceeded(let requestID):
                // Play and pause wait for observation; only a stop is
                // application-owned because no player reports that state.
                guard let change = state.pendingStatusChange,
                    change.requestID == requestID,
                    change.target == .stopped
                else { return .none }

                state.status = .stopped
                state.pendingStatusChange = nil
                return .send(.timeline(.resetPosition))

            case .statusChangeFailed(let requestID, let error):
                guard let change = state.pendingStatusChange,
                    change.requestID == requestID
                else { return .none }

                state.pendingStatusChange = nil
                if let trackID = state.queue.currentTrackID {
                    state.failureNotice = PlaybackFailureNotice(
                        trackID: trackID,
                        failure: error == .unavailable
                            ? .resourceUnavailable
                            : .playbackFailed
                    )
                }
                return .none

            case .previousTapped:
                guard state.canRequestPrevious else { return .none }
                state.failureNotice = nil
                return .send(.queue(.previousTapped))

            case .nextTapped:
                guard state.canRequestNext else { return .none }
                state.failureNotice = nil
                return .send(.queue(.nextTapped))

            case .repeatTapped:
                guard state.canRequestRepeat else { return .none }
                state.failureNotice = nil
                return .send(.queue(.repeatTapped))

            case .shuffleTapped:
                guard state.canRequestShuffle else { return .none }
                state.failureNotice = nil
                return .send(.queue(.shuffleTapped))

            case .timelinePositionChanged(let requestedPosition):
                guard state.canRequestSeek,
                    let duration = state.timelineDuration
                else { return .none }
                let position = min(max(requestedPosition, 0), duration)
                return .send(.timeline(.positionChanged(position)))

            case .timelineInteractionEnded:
                guard state.canRequestSeek,
                    let duration = state.timelineDuration
                else { return .none }
                let position = min(max(state.timeline.position, 0), duration)
                guard position != state.timeline.position else {
                    return .send(.timeline(.dragEnded))
                }
                return .concatenate(
                    .send(.timeline(.positionChanged(position))),
                    .send(.timeline(.dragEnded))
                )

            case .restartTapped:
                guard state.canRequestSeek else { return .none }
                return .send(.timeline(.seekRequested(0)))

            case .seekBackwardTapped:
                guard state.canRequestSeek,
                    let duration = state.timelineDuration
                else { return .none }
                let target = min(max(state.timeline.position - 15, 0), duration)
                return .send(.timeline(.seekRequested(target)))

            case .seekForwardTapped:
                guard state.canRequestSeek,
                    let duration = state.timelineDuration
                else { return .none }
                let target = min(state.timeline.position + 15, duration)
                return .send(.timeline(.seekRequested(target)))

            case .observationReceived(.snapshot(let snapshot)):
                return .send(.reconcileSnapshot(snapshot))

            case .observationReceived(.completed(let trackID)):
                return .send(.currentTrackCompleted(trackID))

            case .observationReceived(.failed(let trackID, let failure)):
                return .send(.runtimePlaybackFailed(trackID, failure))

            case .currentTrackCompleted(let trackID):
                guard state.pendingPlaybackTransition == nil,
                    trackID == state.queue.currentTrackID
                else { return .none }
                return .send(.queue(.currentTrackCompleted(trackID)))

            case .runtimePlaybackFailed(let trackID, let failure):
                // A target that failed at runtime can never confirm itself.
                if let pending = state.pendingPlaybackTransition,
                    trackID == pending.targetTrackID
                {
                    state.failureNotice = PlaybackFailureNotice(
                        trackID: pending.targetTrackID,
                        failure: failure
                    )
                    switch pending.settlement {
                    case .committing, .applyingCommit:
                        return .none
                    case .rollingBack:
                        state.pendingPlaybackTransition?
                            .discardPendingTargetSnapshot()
                        return .none
                    case .none:
                        let installation = pending.installation
                        state.pendingPlaybackTransition?
                            .discardPendingTargetSnapshot()
                        state.pendingPlaybackTransition?.settlement =
                            .rollingBack(
                                .abandoning(
                                    installation,
                                    followUp: .none
                                )
                            )
                        return .concatenate(
                            .cancel(id: CancelID.playbackTransition),
                            rollbackEffect(
                                installation,
                                requestID: pending.requestID
                            )
                        )
                    }
                }

                guard trackID == nil || trackID == state.queue.currentTrackID,
                    let noticeTrackID = trackID ?? state.queue.currentTrackID
                else { return .none }
                state.failureNotice = PlaybackFailureNotice(
                    trackID: noticeTrackID,
                    failure: failure
                )
                return .none

            case .reconcileSnapshot(let snapshot):
                return reconcilePlaybackSnapshot(
                    state: &state,
                    snapshot: snapshot
                )

            case .replayTransitionSnapshot(let requestID, let snapshot):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.confirmationReadiness
                        == .readyForConfirmation,
                    pending.settlement == .none
                else { return .none }
                return reconcilePlaybackSnapshot(
                    state: &state,
                    snapshot: snapshot
                )

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none

            case .timeline(.delegate(.transportFailed(let failure))):
                guard let trackID = state.queue.currentTrackID else {
                    return .none
                }
                state.failureNotice = PlaybackFailureNotice(
                    trackID: trackID,
                    failure: failure
                )
                return .none

            case .queue(.delegate(.transitionRequested(let trackID))):
                let transitionQueue: IdentifiedArrayOf<Track>
                if let pending = state.pendingPlaybackTransition {
                    switch pending.settlement {
                    case .committing, .applyingCommit:
                        transitionQueue = pending.queue
                    case .none, .rollingBack:
                        transitionQueue = state.queue.tracks
                    }
                } else {
                    transitionQueue = state.queue.tracks
                }
                guard transitionQueue[id: trackID] != nil
                else { return .none }

                let requestID = uuid()
                let intent = PendingPlaybackTransition.TransitionIntent(
                    requestID: requestID,
                    queue: transitionQueue,
                    targetTrackID: trackID,
                    origin: .navigation
                )
                if state.pendingPlaybackTransition?
                    .retainLatestFollowUp(.transition(intent)) == true
                {
                    state.failureNotice = nil
                    state.pendingStatusChange = nil
                    return .cancel(id: CancelID.statusChange)
                }

                let rollbackInstallation =
                    state.pendingPlaybackTransition?.rollbackInstallation
                state.pendingPlaybackTransition = PendingPlaybackTransition(
                    requestID: requestID,
                    queue: transitionQueue,
                    targetTrackID: trackID,
                    origin: .navigation,
                    settlement: rollbackInstallation.map {
                        .rollingBack(.superseding($0))
                    } ?? .none
                )
                state.failureNotice = nil
                // A newer transition supersedes an older transport request.
                state.pendingStatusChange = nil
                let transitionEffect: Effect<Action>
                if let rollbackInstallation {
                    transitionEffect = .concatenate(
                        .cancel(id: CancelID.playbackTransition),
                        rollbackEffect(
                            rollbackInstallation,
                            requestID: requestID
                        )
                    )
                } else {
                    transitionEffect = .send(
                        .resolveTransition(
                            requestID: requestID,
                            trackID: trackID
                        )
                    )
                }
                return .concatenate(
                    .cancel(id: CancelID.statusChange),
                    transitionEffect
                )

            case .queue, .timeline:
                return .none
            }
        }
    }

    private func applyConfirmedSnapshotState(
        _ snapshot: PlaybackSnapshot,
        to state: inout State
    ) {
        let preservesStoppedStatus =
            state.status == .stopped
            && snapshot.currentTrackID == state.queue.currentTrackID
            && snapshot.status == .paused
        if !preservesStoppedStatus {
            state.status = snapshot.status
        }
        state.timeline.duration = snapshot.duration
        state.timeline.isSeekable = snapshot.isSeekable
    }

    private func reconcilePlaybackSnapshot(
        state: inout State,
        snapshot: PlaybackSnapshot
    ) -> Effect<Action> {
        if let pending = state.pendingPlaybackTransition {
            switch pending.settlement {
            case .committing(var commit):
                guard
                    snapshot.currentTrackID == pending.targetTrackID
                else { return .none }
                commit.snapshot = snapshot
                state.pendingPlaybackTransition?.settlement =
                    .committing(commit)
                return .none
            case .applyingCommit(var commit):
                guard
                    snapshot.currentTrackID == pending.targetTrackID
                else { return .none }
                commit.snapshot = snapshot
                state.pendingPlaybackTransition?.settlement =
                    .applyingCommit(commit)
                return .none
            case .rollingBack:
                guard
                    snapshot.currentTrackID
                        == state.queue.currentTrackID
                else { return .none }
                return reconcileConfirmedSnapshot(
                    state: &state,
                    snapshot: snapshot
                )
            case .none:
                break
            }

            guard
                let observedTrackID = snapshot.currentTrackID,
                observedTrackID == pending.targetTrackID
            else {
                return reconcileConfirmedSnapshot(
                    state: &state,
                    snapshot: snapshot
                )
            }

            switch pending.confirmationReadiness {
            case .awaitingLoad:
                state.pendingPlaybackTransition?
                    .confirmationReadiness =
                    .awaitingLoad(latestTargetSnapshot: snapshot)
                return .none
            case .awaitingPlay:
                state.pendingPlaybackTransition?
                    .confirmationReadiness =
                    .awaitingPlay(latestTargetSnapshot: snapshot)
                return .none
            case .readyForConfirmation:
                break
            }

            let commit = PendingPlaybackTransition.Commit(
                snapshot: snapshot
            )
            state.pendingPlaybackTransition?.settlement =
                .committing(commit)
            if state.failureNotice?.trackID == observedTrackID {
                state.failureNotice = nil
            }
            let installation = pending.installation
            return .run { send in
                await playbackItem.commit(installation)
                await send(
                    .transitionCommitCompleted(
                        requestID: pending.requestID,
                        installation: installation
                    )
                )
            }
        }

        return reconcileConfirmedSnapshot(
            state: &state,
            snapshot: snapshot
        )
    }

    private func reconcileConfirmedSnapshot(
        state: inout State,
        snapshot: PlaybackSnapshot
    ) -> Effect<Action> {
        state.timeline.duration = snapshot.duration
        state.timeline.isSeekable = snapshot.isSeekable

        // A playback engine may report a stopped session as paused at zero, so
        // the application-owned stop survives until playback reports motion.
        let preservesStoppedStatus =
            state.status == .stopped
            && snapshot.currentTrackID == state.queue.currentTrackID
            && snapshot.status == .paused

        if !preservesStoppedStatus {
            state.status = snapshot.status
        }

        if let change = state.pendingStatusChange {
            let matchesTarget: Bool
            switch change.target {
            case .playing:
                matchesTarget = snapshot.status == .playing
            case .paused:
                matchesTarget = snapshot.status == .paused
            case .stopped:
                matchesTarget = snapshot.status == .stopped
            }
            if matchesTarget {
                state.pendingStatusChange = nil
                state.failureNotice = nil
                let confirmationEffects: [Effect<Action>] =
                    snapshot.currentTrackID.map {
                        [.send(.queue(.currentTrackConfirmed($0)))]
                    } ?? []
                if change.target == .stopped {
                    return .concatenate(
                        [
                            .cancel(id: CancelID.statusChange),
                            .send(.timeline(.resetPosition)),
                        ] + confirmationEffects
                    )
                }
                return .concatenate(
                    [.cancel(id: CancelID.statusChange)]
                        + confirmationEffects
                        + [
                            .send(
                                .timeline(
                                    .positionObserved(snapshot.position)
                                )
                            )
                        ]
                )
            }
        }

        let confirmationEffects: [Effect<Action>] =
            snapshot.currentTrackID.map {
                [.send(.queue(.currentTrackConfirmed($0)))]
            } ?? []
        return .concatenate(
            confirmationEffects
                + [
                    .send(
                        .timeline(
                            .positionObserved(snapshot.position)
                        )
                    )
                ]
        )
    }

    private func rollbackEffect(
        _ installation: PlaybackItemInstallation,
        requestID: UUID
    ) -> Effect<Action> {
        .run { send in
            await playbackItem.rollback(installation)
            await send(.transitionRollbackCompleted(requestID: requestID))
        }
    }
}

extension PlaybackFeature.State {
    var commandPolicy: PlaybackCommandPolicy {
        PlaybackCommandPolicy(
            queue: queue,
            status: status,
            duration: timeline.duration,
            isSeekable: timeline.isSeekable,
            pendingPlaybackTransition: pendingPlaybackTransition,
            pendingStatusChange: pendingStatusChange
        )
    }

    var canRequestPlayPause: Bool { commandPolicy.allows(.playPause) }
    var canRequestStop: Bool { commandPolicy.allows(.stop) }
    var canRequestSeek: Bool { commandPolicy.allows(.seek) }
    var canRequestPrevious: Bool { commandPolicy.allows(.previous) }
    var canRequestNext: Bool { commandPolicy.allows(.next) }
    var canRequestRepeat: Bool { commandPolicy.allows(.repeatMode) }
    var canRequestShuffle: Bool { commandPolicy.allows(.shuffleMode) }

    /// The player-confirmed timeline duration controls seek commands and clamping.
    var timelineDuration: TimeInterval? {
        timeline.duration
    }
}
