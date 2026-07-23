import ComposableArchitecture
import Foundation

/// Owns the confirmed playback queue order, current item identity, and modes.
@Reducer
struct PlaybackQueueFeature {
    @ObservableState
    struct State: Equatable {
        var songs: IdentifiedArrayOf<SongSummary>
        var currentItemID: MusicItemID?
        var repeatMode: PlaybackRepeatMode
        var shuffleMode: PlaybackShuffleMode
        var pendingQueueTransition: PendingQueueTransition?
        var pendingRepeatChange: PendingRepeatChange?
        var pendingShuffleChange: PendingShuffleChange?
    }

    /// Identifies one queue transition awaiting provider observation.
    struct PendingQueueTransition: Equatable {
        let requestID: UUID
        let direction: PlaybackQueueNavigationDirection
    }

    /// Identifies one Repeat request awaiting completion or observation.
    struct PendingRepeatChange: Equatable {
        let requestID: UUID
        let target: PlaybackRepeatMode
    }

    /// Identifies one Shuffle request awaiting completion or observation.
    struct PendingShuffleChange: Equatable {
        let requestID: UUID
        let target: PlaybackShuffleMode
    }

    enum Delegate: Equatable {
        case queueTransitionFailed(MusicProviderError)
        case modeChangeFailed(MusicProviderError)
    }

    enum Action: Equatable {
        case replace(
            IdentifiedArrayOf<SongSummary>,
            startingAt: MusicItemID
        )
        case currentItemObserved(MusicItemID?)
        case cycleRepeatModeRequested(Set<PlaybackRepeatMode>)
        case repeatModeChangeRequested(PlaybackRepeatMode)
        case repeatModeChangeSucceeded(requestID: UUID)
        case repeatModeChangeFailed(
            requestID: UUID,
            error: MusicProviderError
        )
        case repeatModeObserved(PlaybackRepeatMode)
        case toggleShuffleRequested
        case shuffleModeChangeRequested(PlaybackShuffleMode)
        case shuffleModeChangeSucceeded(requestID: UUID)
        case shuffleModeChangeFailed(
            requestID: UUID,
            error: MusicProviderError
        )
        case shuffleModeObserved(PlaybackShuffleMode)
        case queueTransitionRequested(PlaybackQueueNavigationDirection)
        case queueTransitionFailed(
            requestID: UUID,
            error: MusicProviderError
        )
        case queueTransitionReachedBoundary(requestID: UUID)
        case cancelQueueTransition
        case reset
        case delegate(Delegate)
    }

    private enum CancelID {
        case queueTransition
        case repeatModeChange
        case shuffleModeChange
    }

    @Dependency(\.playbackQueue) var playbackQueue
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .replace(let songs, let startingItemID):
                guard songs[id: startingItemID] != nil else {
                    return .none
                }
                state.songs = songs
                state.currentItemID = startingItemID
                state.pendingQueueTransition = nil
                state.pendingRepeatChange = nil
                state.pendingShuffleChange = nil
                return .merge(
                    .cancel(id: CancelID.queueTransition),
                    .cancel(id: CancelID.repeatModeChange),
                    .cancel(id: CancelID.shuffleModeChange)
                )

            case .currentItemObserved(let itemID):
                guard let itemID,
                    state.songs[id: itemID] != nil
                else { return .none }
                guard itemID != state.currentItemID else { return .none }
                state.currentItemID = itemID
                state.pendingQueueTransition = nil
                return .none

            case .cycleRepeatModeRequested(let supportedModes):
                let cycleOrder = PlaybackRepeatMode.cycleOrder
                guard state.pendingRepeatChange == nil,
                    let currentIndex = cycleOrder.firstIndex(
                        of: state.repeatMode
                    )
                else { return .none }

                for offset in 1..<cycleOrder.count {
                    let index = (currentIndex + offset) % cycleOrder.count
                    let target = cycleOrder[index]
                    if supportedModes.contains(target) {
                        return .send(.repeatModeChangeRequested(target))
                    }
                }

                return .none

            case .repeatModeChangeRequested(let target):
                guard !state.songs.isEmpty,
                    state.currentItemID != nil,
                    state.pendingRepeatChange == nil
                else { return .none }
                let requestID = uuid()
                state.pendingRepeatChange = PendingRepeatChange(
                    requestID: requestID,
                    target: target
                )
                return .run { send in
                    do {
                        try await playbackQueue.setRepeat(target)
                        try Task.checkCancellation()
                        await send(
                            .repeatModeChangeSucceeded(requestID: requestID)
                        )
                    } catch is CancellationError {
                        return
                    } catch let error as MusicProviderError {
                        guard !Task.isCancelled else { return }
                        await send(
                            .repeatModeChangeFailed(
                                requestID: requestID,
                                error: error
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .repeatModeChangeFailed(
                                requestID: requestID,
                                error: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.repeatModeChange)

            case .repeatModeChangeSucceeded(let requestID):
                guard let pending = state.pendingRepeatChange,
                    pending.requestID == requestID
                else { return .none }
                state.repeatMode = pending.target
                state.pendingRepeatChange = nil
                return .none

            case .repeatModeChangeFailed(let requestID, let error):
                guard state.pendingRepeatChange?.requestID == requestID else {
                    return .none
                }
                state.pendingRepeatChange = nil
                return .send(.delegate(.modeChangeFailed(error)))

            case .repeatModeObserved(let mode):
                state.repeatMode = mode
                guard state.pendingRepeatChange?.target == mode else {
                    return .none
                }
                state.pendingRepeatChange = nil
                return .cancel(id: CancelID.repeatModeChange)

            case .toggleShuffleRequested:
                guard state.pendingShuffleChange == nil else {
                    return .none
                }
                let target: PlaybackShuffleMode =
                    state.shuffleMode == .off ? .songs : .off
                return .send(.shuffleModeChangeRequested(target))

            case .shuffleModeChangeRequested(let target):
                guard !state.songs.isEmpty,
                    state.currentItemID != nil,
                    state.pendingShuffleChange == nil
                else { return .none }
                let requestID = uuid()
                state.pendingShuffleChange = PendingShuffleChange(
                    requestID: requestID,
                    target: target
                )
                return .run { send in
                    do {
                        try await playbackQueue.setShuffle(target)
                        try Task.checkCancellation()
                        await send(
                            .shuffleModeChangeSucceeded(requestID: requestID)
                        )
                    } catch is CancellationError {
                        return
                    } catch let error as MusicProviderError {
                        guard !Task.isCancelled else { return }
                        await send(
                            .shuffleModeChangeFailed(
                                requestID: requestID,
                                error: error
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .shuffleModeChangeFailed(
                                requestID: requestID,
                                error: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.shuffleModeChange)

            case .shuffleModeChangeSucceeded(let requestID):
                guard let pending = state.pendingShuffleChange,
                    pending.requestID == requestID
                else { return .none }
                state.shuffleMode = pending.target
                state.pendingShuffleChange = nil
                return .none

            case .shuffleModeChangeFailed(let requestID, let error):
                guard state.pendingShuffleChange?.requestID == requestID else {
                    return .none
                }
                state.pendingShuffleChange = nil
                return .send(.delegate(.modeChangeFailed(error)))

            case .shuffleModeObserved(let mode):
                state.shuffleMode = mode
                guard state.pendingShuffleChange?.target == mode else {
                    return .none
                }
                state.pendingShuffleChange = nil
                return .cancel(id: CancelID.shuffleModeChange)

            case .queueTransitionRequested(let direction):
                guard !state.songs.isEmpty,
                    state.currentItemID != nil,
                    state.pendingQueueTransition == nil
                else { return .none }
                let requestID = uuid()
                state.pendingQueueTransition = PendingQueueTransition(
                    requestID: requestID,
                    direction: direction
                )
                return .run { send in
                    do {
                        let result = try await playbackQueue.navigate(
                            direction
                        )
                        if result == .boundaryReached {
                            await send(
                                .queueTransitionReachedBoundary(
                                    requestID: requestID
                                )
                            )
                        }
                    } catch is CancellationError {
                        return
                    } catch let error as MusicProviderError {
                        guard !Task.isCancelled else { return }
                        await send(
                            .queueTransitionFailed(
                                requestID: requestID,
                                error: error
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .queueTransitionFailed(
                                requestID: requestID,
                                error: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.queueTransition)

            case .queueTransitionReachedBoundary(let requestID):
                guard state.pendingQueueTransition?.requestID == requestID else {
                    return .none
                }
                state.pendingQueueTransition = nil
                return .none

            case .queueTransitionFailed(let requestID, let error):
                guard state.pendingQueueTransition?.requestID == requestID else {
                    return .none
                }
                state.pendingQueueTransition = nil
                return .send(.delegate(.queueTransitionFailed(error)))

            case .cancelQueueTransition:
                state.pendingQueueTransition = nil
                return .cancel(id: CancelID.queueTransition)

            case .reset:
                state.songs = []
                state.currentItemID = nil
                state.repeatMode = .off
                state.shuffleMode = .off
                state.pendingQueueTransition = nil
                state.pendingRepeatChange = nil
                state.pendingShuffleChange = nil
                return .merge(
                    .cancel(id: CancelID.queueTransition),
                    .cancel(id: CancelID.repeatModeChange),
                    .cancel(id: CancelID.shuffleModeChange)
                )

            case .delegate:
                return .none
            }
        }
    }
}

extension PlaybackQueueFeature.State {
    var currentItem: SongSummary? {
        guard let currentItemID else { return nil }
        return songs[id: currentItemID]
    }
}
