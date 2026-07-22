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
        var failure: MusicProviderError?
        var playbackEligibility: CatalogPlaybackEligibility
        var capabilities: MusicProviderCapabilities
        var timeline: PlaybackTimelineFeature.State
        var pendingOperation: PendingOperation?
        var pendingReset: PendingReset?
        var isPlayerPresented: Bool
    }

    enum PendingOperation: Equatable {
        case queueReplacement(PendingQueueReplacement)
        case statusChange(PendingStatusChange)
    }

    struct PendingQueueReplacement: Equatable {
        let requestID: UUID
        let songs: IdentifiedArrayOf<SongSummary>
        let startingItemID: MusicItemID
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

    struct PendingReset: Equatable {
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
            SongSummary,
            loadedResults: IdentifiedArrayOf<SongSummary>,
            providerID: ProviderID,
            playbackEligibility: CatalogPlaybackEligibility
        )
        case performQueueReplacement(
            requestID: UUID,
            itemIDs: [MusicItemID],
            startingItemID: MusicItemID
        )
        case queueReplacementSucceeded(requestID: UUID)
        case queueReplacementFailed(
            requestID: UUID,
            error: MusicProviderError
        )
        case cancelPendingOperation
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
        case setPlayerPresented(Bool)
        case snapshotReceived(PlaybackSnapshot)
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
        case parentOperation
    }

    @Dependency(\.playbackControl) var playbackControl
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
                guard state.pendingReset == nil else { return .none }
                return .run { send in
                    let snapshots = await playbackObservation.playbackSnapshots()
                    for await snapshot in snapshots {
                        await send(.snapshotReceived(snapshot))
                    }
                }
                .cancellable(
                    id: CancelID.playbackObservation,
                    cancelInFlight: true
                )

            case .reset(let providerID, let capabilities):
                let requestID = uuid()
                state.pendingReset = PendingReset(
                    requestID: requestID,
                    providerID: providerID,
                    capabilities: capabilities
                )
                return .concatenate(
                    .merge(
                        .cancel(id: CancelID.playbackObservation),
                        .cancel(id: CancelID.parentOperation)
                    ),
                    .send(.queue(.reset)),
                    .send(.timeline(.reset)),
                    .send(.applyReset(requestID: requestID))
                )

            case .applyReset(let requestID):
                guard let pendingReset = state.pendingReset,
                    pendingReset.requestID == requestID
                else { return .none }

                state.providerID = pendingReset.providerID
                state.status = .idle
                state.failure = nil
                state.playbackEligibility = .unknown
                state.capabilities = pendingReset.capabilities
                state.pendingOperation = nil
                state.pendingReset = nil
                state.isPlayerPresented = false
                return .send(
                    .delegate(.resetCompleted(pendingReset.providerID))
                )

            case .delegate:
                return .none

            case .selectionReceived(
                let song,
                let loadedResults,
                let providerID,
                let playbackEligibility
            ):
                let hasNowPlaying = !state.queue.songs.isEmpty
                guard state.pendingReset == nil,
                    state.providerID == providerID,
                    playbackEligibility == .eligible,
                    state.capabilities.supportsEmbeddedPlayback,
                    state.capabilities.supportsQueueReplacement,
                    loadedResults[id: song.id] != nil,
                    loadedResults.allSatisfy({ $0.id.providerID == providerID })
                else {
                    if state.pendingReset == nil,
                        state.providerID == providerID,
                        playbackEligibility != .eligible,
                        !hasNowPlaying
                    {
                        state.playbackEligibility = playbackEligibility
                        state.failure = nil
                        state.isPlayerPresented = true
                    }
                    return .none
                }

                if !hasNowPlaying {
                    state.isPlayerPresented = true
                }
                let requestID = uuid()
                state.pendingOperation = .queueReplacement(
                    PendingQueueReplacement(
                        requestID: requestID,
                        songs: loadedResults,
                        startingItemID: song.id
                    )
                )
                state.playbackEligibility = .eligible
                state.failure = nil
                return .send(
                    .performQueueReplacement(
                        requestID: requestID,
                        itemIDs: Array(loadedResults.ids),
                        startingItemID: song.id
                    )
                )

            case .performQueueReplacement(
                let requestID,
                let itemIDs,
                let startingItemID
            ):
                guard state.pendingReset == nil,
                    case .queueReplacement(let replacement) =
                        state.pendingOperation,
                    replacement.requestID == requestID
                else { return .none }
                return .run { send in
                    do {
                        try await playbackControl.playQueue(
                            itemIDs,
                            startingItemID
                        )
                        try Task.checkCancellation()
                        await send(
                            .queueReplacementSucceeded(requestID: requestID)
                        )
                    } catch is CancellationError {
                        return
                    } catch let error as MusicProviderError {
                        guard !Task.isCancelled else { return }
                        await send(
                            .queueReplacementFailed(
                                requestID: requestID,
                                error: error
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .queueReplacementFailed(
                                requestID: requestID,
                                error: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.parentOperation,
                    cancelInFlight: true
                )

            case .queueReplacementSucceeded(let requestID):
                guard
                    case .queueReplacement(let replacement) =
                        state.pendingOperation,
                    replacement.requestID == requestID
                else { return .none }

                state.pendingOperation = nil
                state.status = .playing
                state.failure = nil
                return .concatenate(
                    .send(
                        .queue(
                            .replace(
                                replacement.songs,
                                startingAt: replacement.startingItemID
                            )
                        )
                    ),
                    .send(.timeline(.reset))
                )

            case .queueReplacementFailed(let requestID, let error):
                guard
                    case .queueReplacement(let replacement) =
                        state.pendingOperation,
                    replacement.requestID == requestID
                else { return .none }

                state.pendingOperation = nil
                state.failure = error
                return .none

            case .cancelPendingOperation:
                state.pendingOperation = nil
                return .cancel(id: CancelID.parentOperation)

            case .playPauseTapped:
                guard state.canRequestPlayPause else { return .none }
                let target: PendingStatusChange.Target =
                    state.status == .playing ? .paused : .playing
                let requestID = uuid()
                state.pendingOperation = .statusChange(
                    PendingStatusChange(requestID: requestID, target: target)
                )
                state.failure = nil
                return .send(
                    .performStatusChange(
                        requestID: requestID,
                        target: target
                    )
                )

            case .stopTapped:
                guard state.canRequestStop else { return .none }
                let requestID = uuid()
                state.pendingOperation = .statusChange(
                    PendingStatusChange(requestID: requestID, target: .stopped)
                )
                state.failure = nil
                return .send(
                    .performStatusChange(
                        requestID: requestID,
                        target: .stopped
                    )
                )

            case .performStatusChange(let requestID, let target):
                guard state.pendingReset == nil,
                    case .statusChange(let change) = state.pendingOperation,
                    change.requestID == requestID,
                    change.target == target
                else { return .none }
                return .run { send in
                    do {
                        switch target {
                        case .playing:
                            try await playbackControl.resume()
                        case .paused:
                            try await playbackControl.pause()
                        case .stopped:
                            try await playbackControl.stop()
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
                    id: CancelID.parentOperation,
                    cancelInFlight: true
                )

            case .statusChangeSucceeded(let requestID):
                guard
                    case .statusChange(let change) = state.pendingOperation,
                    change.requestID == requestID
                else { return .none }

                state.pendingOperation = nil
                state.failure = nil
                switch change.target {
                case .playing:
                    state.status = .playing
                    return .none
                case .paused:
                    state.status = .paused
                    return .none
                case .stopped:
                    state.status = .stopped
                    return .send(.timeline(.reset))
                }

            case .statusChangeFailed(let requestID, let error):
                guard
                    case .statusChange(let change) = state.pendingOperation,
                    change.requestID == requestID
                else { return .none }

                state.pendingOperation = nil
                state.failure = error
                return .none

            case .timelinePositionChanged(let requestedPosition):
                guard state.canRequestSeek,
                    let duration = state.queue.currentItem?.duration
                else { return .none }
                let position = min(max(requestedPosition, 0), duration)
                return .send(.timeline(.positionChanged(position)))

            case .timelineInteractionEnded:
                guard state.canRequestSeek else { return .none }
                return .send(.timeline(.dragEnded))

            case .restartTapped:
                guard state.canRequestSeek else { return .none }
                return .send(.timeline(.seekRequested(0)))

            case .seekBackwardTapped:
                guard state.canRequestSeek else { return .none }
                let target = max(state.timeline.position - 15, 0)
                return .send(.timeline(.seekRequested(target)))

            case .seekForwardTapped:
                guard state.canRequestSeek,
                    let duration = state.queue.currentItem?.duration
                else { return .none }
                let target = min(state.timeline.position + 15, duration)
                return .send(.timeline(.seekRequested(target)))

            case .snapshotReceived(let snapshot):
                guard state.pendingReset == nil else { return .none }
                state.status = snapshot.status

                if case .queueReplacement(let replacement) =
                    state.pendingOperation,
                    snapshot.status == .playing,
                    snapshot.currentItemID == replacement.startingItemID
                {
                    state.pendingOperation = nil
                    state.failure = nil
                    return .concatenate(
                        .cancel(id: CancelID.parentOperation),
                        .send(
                            .queue(
                                .replace(
                                    replacement.songs,
                                    startingAt: replacement.startingItemID
                                )
                            )
                        ),
                        .send(.timeline(.reset)),
                        .send(
                            .timeline(
                                .positionObserved(snapshot.currentTime)
                            )
                        )
                    )
                }

                if case .statusChange(let change) = state.pendingOperation {
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
                        state.pendingOperation = nil
                        state.failure = nil
                        if change.target == .stopped {
                            return .concatenate(
                                .cancel(id: CancelID.parentOperation),
                                .send(.timeline(.reset)),
                                .send(
                                    .queue(
                                        .currentItemObserved(
                                            snapshot.currentItemID
                                        )
                                    )
                                )
                            )
                        }
                        return .concatenate(
                            .cancel(id: CancelID.parentOperation),
                            .send(
                                .queue(
                                    .currentItemObserved(snapshot.currentItemID)
                                )
                            ),
                            .send(
                                .timeline(
                                    .positionObserved(snapshot.currentTime)
                                )
                            )
                        )
                    }
                }

                return .concatenate(
                    .send(
                        .queue(
                            .currentItemObserved(snapshot.currentItemID)
                        )
                    ),
                    .send(
                        .timeline(
                            .positionObserved(snapshot.currentTime)
                        )
                    )
                )

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none

            case .timeline(.delegate(.transportFailed(let error))):
                state.failure = error
                return .none

            case .queue, .timeline:
                return .none
            }
        }
    }
}

extension PlaybackFeature.State {
    var canRequestPlayPause: Bool {
        !queue.songs.isEmpty
            && capabilities.supportsEmbeddedPlayback
            && pendingOperation == nil
            && pendingReset == nil
    }

    var canRequestStop: Bool {
        guard capabilities.supportsEmbeddedPlayback,
            pendingReset == nil
        else { return false }
        switch pendingOperation {
        case .queueReplacement:
            return true
        case .statusChange:
            return false
        case nil:
            return !queue.songs.isEmpty && status != .stopped
        }
    }

    var canRequestSeek: Bool {
        guard pendingReset == nil,
            capabilities.supportsSeeking,
            let duration = queue.currentItem?.duration
        else { return false }
        return duration > 0
    }
}
