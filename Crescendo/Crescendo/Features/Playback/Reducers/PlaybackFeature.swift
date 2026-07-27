import ComposableArchitecture
import Foundation

/// Owns confirmed playback state and coordinates playback-domain workflows.
@Reducer
struct PlaybackFeature {
    @ObservableState
    struct State: Equatable {
        var providerID: ProviderID?
        var queue: PlaybackQueueFeature.State
        var status: PlaybackStatus
        var failureNotice: PlaybackFailureNotice?
        var playbackEligibility: CatalogPlaybackEligibility
        var capabilities: MusicProviderCapabilities
        var timeline: PlaybackTimelineFeature.State
        var pendingPlaybackTransition: PendingPlaybackTransition?
        var pendingStatusChange: PendingStatusChange?
        var pendingProviderReset: PendingProviderReset?
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

    struct PendingProviderReset: Equatable {
        let requestID: UUID
        let providerID: ProviderID
        let capabilities: MusicProviderCapabilities
    }

    enum Delegate: Equatable {
        case resetCompleted(ProviderID)
    }

    enum Action: Equatable {
        case task
        case reset(
            providerID: ProviderID,
            capabilities: MusicProviderCapabilities
        )
        case applyReset(requestID: UUID)
        case delegate(Delegate)
        case selectionReceived(
            TrackID,
            loadedResults: IdentifiedArrayOf<Track>,
            providerID: ProviderID,
            playbackEligibility: CatalogPlaybackEligibility
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
                guard state.pendingProviderReset == nil else { return .none }
                return .run { send in
                    let observations = await playbackObservation.observations()
                    for await observation in observations {
                        await send(.observationReceived(observation))
                    }
                }
                .cancellable(
                    id: CancelID.playbackObservation,
                    cancelInFlight: true
                )

            case .reset(let providerID, let capabilities):
                let requestID = uuid()
                state.pendingProviderReset = PendingProviderReset(
                    requestID: requestID,
                    providerID: providerID,
                    capabilities: capabilities
                )
                return .concatenate(
                    .merge(
                        .cancel(id: CancelID.playbackObservation),
                        .cancel(id: CancelID.playbackTransition),
                        .cancel(id: CancelID.statusChange)
                    ),
                    .send(.queue(.reset)),
                    .send(.timeline(.reset)),
                    .send(.applyReset(requestID: requestID))
                )

            case .applyReset(let requestID):
                guard let pendingProviderReset = state.pendingProviderReset,
                    pendingProviderReset.requestID == requestID
                else { return .none }

                state.providerID = pendingProviderReset.providerID
                state.status = .idle
                state.failureNotice = nil
                state.playbackEligibility = .unknown
                state.capabilities = pendingProviderReset.capabilities
                state.pendingPlaybackTransition = nil
                state.pendingStatusChange = nil
                state.pendingProviderReset = nil
                state.isPlayerPresented = false
                return .send(
                    .delegate(.resetCompleted(pendingProviderReset.providerID))
                )

            case .delegate:
                return .none

            case .selectionReceived(
                let trackID,
                let loadedResults,
                let providerID,
                let playbackEligibility
            ):
                let hasNowPlaying = !state.queue.tracks.isEmpty
                guard state.pendingProviderReset == nil,
                    state.providerID == providerID,
                    playbackEligibility == .eligible,
                    state.capabilities.supportsEmbeddedPlayback,
                    loadedResults[id: trackID] != nil,
                    loadedResults.allSatisfy({ $0.id.providerID == providerID })
                else {
                    if state.pendingProviderReset == nil,
                        state.providerID == providerID,
                        playbackEligibility != .eligible,
                        !hasNowPlaying
                    {
                        state.playbackEligibility = playbackEligibility
                        state.failureNotice = nil
                        state.isPlayerPresented = true
                    }
                    return .none
                }

                if !hasNowPlaying {
                    state.isPlayerPresented = true
                }
                let requestID = uuid()
                state.pendingPlaybackTransition = PendingPlaybackTransition(
                    requestID: requestID,
                    queue: loadedResults,
                    targetTrackID: trackID,
                    origin: .selection
                )
                state.playbackEligibility = .eligible
                state.failureNotice = nil
                // A newer selection supersedes an older transport request.
                state.pendingStatusChange = nil
                return .concatenate(
                    .cancel(id: CancelID.statusChange),
                    .send(
                        .resolveTransition(
                            requestID: requestID,
                            trackID: trackID
                        )
                    )
                )

            case .resolveTransition(let requestID, let trackID):
                guard state.pendingProviderReset == nil,
                    let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.targetTrackID == trackID
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
                    pending.targetTrackID == resource.trackID
                else { return .none }
                return .send(
                    .loadTransition(requestID: requestID, resource: resource)
                )

            case .loadTransition(let requestID, let resource):
                guard state.pendingProviderReset == nil,
                    let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID,
                    pending.targetTrackID == resource.trackID
                else { return .none }
                return .run { send in
                    do {
                        try await playbackItem.load(resource)
                        try Task.checkCancellation()
                        await send(.transitionItemLoaded(requestID: requestID))
                    } catch is CancellationError {
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
                guard
                    state.pendingPlaybackTransition?.requestID == requestID
                else { return .none }
                // The player now holds the target item, so a snapshot bearing
                // the target identity can finally be trusted as installation.
                state.pendingPlaybackTransition?.hasLoadedItem = true
                return .send(.playTransition(requestID: requestID))

            case .playTransition(let requestID):
                guard state.pendingProviderReset == nil,
                    let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID
                else { return .none }
                let trackID = pending.targetTrackID
                return .run { send in
                    do {
                        try await playbackTransport.play()
                        try Task.checkCancellation()
                        await send(
                            .transitionPlayRequested(requestID: requestID)
                        )
                    } catch is CancellationError {
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

            case .transitionPlayRequested:
                // Observation stays authoritative; nothing is confirmed here.
                return .none

            case .transitionResolutionFailed(let requestID, let failure),
                .transitionItemLoadFailed(let requestID, let failure):
                guard let pending = state.pendingPlaybackTransition,
                    pending.requestID == requestID
                else { return .none }

                state.failureNotice = PlaybackFailureNotice(
                    trackID: pending.targetTrackID,
                    failure: failure
                )
                state.pendingPlaybackTransition = nil
                return .none

            case .transitionPlayFailed(
                let requestID,
                let trackID,
                let failure
            ):
                if let pending = state.pendingPlaybackTransition {
                    guard pending.requestID == requestID,
                        pending.targetTrackID == trackID
                    else { return .none }
                    state.pendingPlaybackTransition = nil
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
                state.pendingPlaybackTransition = nil
                return .cancel(id: CancelID.playbackTransition)

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
                state.pendingPlaybackTransition = nil
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
                guard state.pendingProviderReset == nil,
                    let change = state.pendingStatusChange,
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
                            try await playbackTransport.pause()
                            try await playbackTimeline.seek(0)
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
                guard state.pendingProviderReset == nil,
                    state.pendingPlaybackTransition == nil,
                    trackID == state.queue.currentTrackID
                else { return .none }
                return .send(.queue(.currentTrackCompleted(trackID)))

            case .runtimePlaybackFailed(let trackID, let failure):
                guard state.pendingProviderReset == nil else { return .none }

                // A target that failed at runtime can never confirm itself.
                if let pending = state.pendingPlaybackTransition,
                    trackID == pending.targetTrackID
                {
                    state.failureNotice = PlaybackFailureNotice(
                        trackID: pending.targetTrackID,
                        failure: failure
                    )
                    state.pendingPlaybackTransition = nil
                    return .cancel(id: CancelID.playbackTransition)
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
                guard state.pendingProviderReset == nil else { return .none }
                state.timeline.duration = snapshot.duration

                // AVPlayer reports a stopped session as paused at zero, so the
                // application-owned stop survives until the player reports
                // motion of its own.
                let preservesStoppedStatus =
                    state.status == .stopped
                    && snapshot.currentTrackID == state.queue.currentTrackID
                    && snapshot.status == .paused

                // Identity alone cannot confirm a target that is already the
                // confirmed track, because the player still holds the old item
                // until loading completes. Requiring the loaded stage keeps a
                // stale snapshot from confirming a restart or a Repeat one.
                if let pending = state.pendingPlaybackTransition,
                    pending.hasLoadedItem,
                    let observedTrackID = snapshot.currentTrackID,
                    observedTrackID == pending.targetTrackID
                {
                    state.pendingPlaybackTransition = nil
                    if state.failureNotice?.trackID == observedTrackID {
                        state.failureNotice = nil
                    }
                    if !preservesStoppedStatus {
                        state.status = snapshot.status
                    }
                    // Only a genuinely new queue may reset traversal order and
                    // the confirmed Repeat and Shuffle modes.
                    let queueEffect: Effect<Action>
                    switch pending.origin {
                    case .selection:
                        queueEffect = .send(
                            .queue(
                                .replace(
                                    pending.queue,
                                    startingAt: observedTrackID
                                )
                            )
                        )
                    case .navigation:
                        queueEffect = .send(
                            .queue(.currentTrackConfirmed(observedTrackID))
                        )
                    }
                    return .concatenate(
                        queueEffect,
                        .send(
                            .timeline(.positionObserved(snapshot.position))
                        )
                    )
                }

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
                guard state.pendingProviderReset == nil,
                    state.queue.tracks[id: trackID] != nil
                else { return .none }

                let requestID = uuid()
                state.pendingPlaybackTransition = PendingPlaybackTransition(
                    requestID: requestID,
                    queue: state.queue.tracks,
                    targetTrackID: trackID,
                    origin: .navigation
                )
                state.failureNotice = nil
                // A newer transition supersedes an older transport request.
                state.pendingStatusChange = nil
                return .concatenate(
                    .cancel(id: CancelID.statusChange),
                    .send(
                        .resolveTransition(
                            requestID: requestID,
                            trackID: trackID
                        )
                    )
                )

            case .queue, .timeline:
                return .none
            }
        }
    }
}

extension PlaybackFeature.State {
    var commandPolicy: PlaybackCommandPolicy {
        PlaybackCommandPolicy(
            capabilities: capabilities,
            queue: queue,
            status: status,
            duration: timelineDuration,
            pendingPlaybackTransition: pendingPlaybackTransition,
            pendingStatusChange: pendingStatusChange,
            isResettingProvider: pendingProviderReset != nil
        )
    }

    var canRequestPlayPause: Bool { commandPolicy.allows(.playPause) }
    var canRequestStop: Bool { commandPolicy.allows(.stop) }
    var canRequestSeek: Bool { commandPolicy.allows(.seek) }
    var canRequestPrevious: Bool { commandPolicy.allows(.previous) }
    var canRequestNext: Bool { commandPolicy.allows(.next) }
    var canRequestRepeat: Bool { commandPolicy.allows(.repeatMode) }
    var canRequestShuffle: Bool { commandPolicy.allows(.shuffleMode) }

    /// Uses player-confirmed duration when available, otherwise catalog metadata.
    var timelineDuration: TimeInterval? {
        timeline.duration ?? queue.currentTrack?.duration
    }
}
