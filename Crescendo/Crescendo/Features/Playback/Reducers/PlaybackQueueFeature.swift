import ComposableArchitecture
import Foundation

/// Owns the confirmed playback queue order and current item identity.
@Reducer
struct PlaybackQueueFeature {
    @ObservableState
    struct State: Equatable {
        var songs: IdentifiedArrayOf<SongSummary>
        var currentItemID: MusicItemID?
        var pendingQueueTransition: PendingQueueTransition?
    }

    /// Identifies one queue transition awaiting provider observation.
    struct PendingQueueTransition: Equatable {
        let requestID: UUID
        let direction: PlaybackNavigationDirection
    }

    enum Delegate: Equatable {
        case queueTransitionFailed(MusicProviderError)
    }

    enum Action: Equatable {
        case replace(
            IdentifiedArrayOf<SongSummary>,
            startingAt: MusicItemID
        )
        case currentItemObserved(MusicItemID?)
        case queueTransitionRequested(PlaybackNavigationDirection)
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
    }

    @Dependency(\.playbackNavigation) var playbackNavigation
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
                return .cancel(id: CancelID.queueTransition)

            case .currentItemObserved(let itemID):
                guard let itemID,
                    state.songs[id: itemID] != nil
                else { return .none }
                guard itemID != state.currentItemID else { return .none }
                state.currentItemID = itemID
                state.pendingQueueTransition = nil
                return .none

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
                        let result = try await playbackNavigation.navigate(
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
                state.pendingQueueTransition = nil
                return .cancel(id: CancelID.queueTransition)

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
