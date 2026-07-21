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
    }

    enum PendingOperation: Equatable {
        case queueReplacement(PendingQueueReplacement)
    }

    struct PendingQueueReplacement: Equatable {
        let requestID: UUID
        let songs: IdentifiedArrayOf<SongSummary>
        let startingItemID: MusicItemID
    }

    enum Action: Equatable {
        case task
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
        case playTapped
        case pauseTapped
        case stopTapped
        case transportFinished
        case transportFailed(MusicProviderError)
        case snapshotReceived(PlaybackSnapshot)
        case queue(PlaybackQueueFeature.Action)
        case timeline(PlaybackTimelineFeature.Action)
    }

    private enum CancelID {
        case playbackObservation
        case queueReplacement
        case transport
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

            case .selectionReceived(
                let song,
                let loadedResults,
                let providerID,
                let playbackEligibility
            ):
                guard state.providerID == providerID,
                    playbackEligibility == .eligible,
                    state.capabilities.supportsEmbeddedPlayback,
                    state.capabilities.supportsQueueReplacement,
                    loadedResults[id: song.id] != nil,
                    loadedResults.allSatisfy({ $0.id.providerID == providerID })
                else {
                    if state.providerID == providerID,
                        playbackEligibility != .eligible,
                        state.queue.songs.isEmpty
                    {
                        state.playbackEligibility = playbackEligibility
                        state.failure = nil
                    }
                    return .none
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
                    id: CancelID.queueReplacement,
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
                return .cancel(id: CancelID.queueReplacement)

            case .playTapped:
                guard state.status == .paused,
                    state.queue.currentItem != nil
                else { return .none }
                state.failure = nil
                return .run { send in
                    do {
                        try await playbackControl.resume()
                        await send(.transportFinished)
                    } catch let error as MusicProviderError {
                        await send(.transportFailed(error))
                    } catch {
                        await send(.transportFailed(.playbackFailed))
                    }
                }
                .cancellable(id: CancelID.transport, cancelInFlight: true)

            case .pauseTapped:
                state.failure = nil
                return .run { send in
                    do {
                        try await playbackControl.pause()
                        await send(.transportFinished)
                    } catch let error as MusicProviderError {
                        await send(.transportFailed(error))
                    } catch {
                        await send(.transportFailed(.playbackFailed))
                    }
                }
                .cancellable(id: CancelID.transport, cancelInFlight: true)

            case .stopTapped:
                state.failure = nil
                return .concatenate(
                    .send(.timeline(.reset)),
                    .run { send in
                        do {
                            try await playbackControl.stop()
                            await send(.transportFinished)
                        } catch let error as MusicProviderError {
                            await send(.transportFailed(error))
                        } catch {
                            await send(.transportFailed(.playbackFailed))
                        }
                    }
                    .cancellable(id: CancelID.transport, cancelInFlight: true)
                )

            case .transportFinished:
                return .none

            case .transportFailed(let error):
                state.failure = error
                return .none

            case .snapshotReceived(let snapshot):
                state.status = snapshot.status

                if case .queueReplacement(let replacement) =
                    state.pendingOperation,
                    snapshot.status == .playing,
                    snapshot.currentItemID == replacement.startingItemID
                {
                    state.pendingOperation = nil
                    state.failure = nil
                    return .concatenate(
                        .cancel(id: CancelID.queueReplacement),
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

            case .timeline(.delegate(.transportFailed(let error))):
                state.failure = error
                return .none

            case .queue, .timeline:
                return .none
            }
        }
    }
}
