import ComposableArchitecture

/// Owns the playback queue contents, traversal order, current identity, and modes.
@Reducer
struct PlaybackQueueReducer {
    @ObservableState
    struct State: Equatable {
        var current: PlaybackQueue?
        var pendingChanges: PendingChanges? = nil
    }

    struct PendingChanges: Equatable {
        var active: QueueChange
        var followUp: QueueChange?

        var latest: QueueChange {
            followUp ?? active
        }
    }

    enum QueueChange: Equatable {
        case replacement(PlaybackQueue)
        case navigation(to: TrackID)

        var targetTrackID: TrackID {
            switch self {
            case .replacement(let queue):
                return queue.currentTrackID
            case .navigation(let trackID):
                return trackID
            }
        }

        func targetTrack(in current: PlaybackQueue?) -> Track? {
            switch self {
            case .replacement(let queue):
                return queue.currentTrack
            case .navigation(let trackID):
                return current?.tracks[id: trackID]
            }
        }

        func applying(to current: PlaybackQueue?) -> PlaybackQueue? {
            switch self {
            case .replacement(let queue):
                return queue
            case .navigation(let trackID):
                return current?.navigating(to: trackID)
            }
        }
    }

    enum Delegate: Equatable {
        case transitionRequested(TrackID)
    }

    enum Action: Equatable {
        case replace(
            IdentifiedArrayOf<Track>,
            startingAt: TrackID
        )
        case selectionRequested(
            TrackID,
            loadedResults: IdentifiedArrayOf<Track>
        )
        case pendingChangeConfirmed(TrackID)
        case pendingFollowUpDiscarded
        case pendingChangesDiscarded
        case currentTrackConfirmed(TrackID)
        case previousTapped
        case nextTapped
        case currentTrackCompleted(TrackID)
        case repeatTapped
        case shuffleTapped
        case reset
        case delegate(Delegate)
    }

    @Dependency(\.playbackShuffle) var playbackShuffle

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .replace(let tracks, let startingTrackID):
                guard
                    let replacement = PlaybackQueue(
                        tracks: tracks,
                        startingAt: startingTrackID
                    )
                else {
                    return .none
                }
                state.current = replacement
                state.pendingChanges = nil
                return .none

            case .selectionRequested(
                let trackID,
                let loadedResults
            ):
                guard
                    let replacement = PlaybackQueue(
                        tracks: loadedResults,
                        startingAt: trackID
                    )
                else {
                    return .none
                }
                let change = QueueChange.replacement(replacement)
                if state.pendingChanges == nil {
                    state.pendingChanges = PendingChanges(
                        active: change,
                        followUp: nil
                    )
                } else {
                    state.pendingChanges?.followUp = change
                }
                return .send(.delegate(.transitionRequested(trackID)))

            case .pendingChangeConfirmed(let trackID):
                guard let pendingChanges = state.pendingChanges else {
                    return .none
                }

                let confirmedChange: QueueChange
                let remainingChanges: PendingChanges?
                if pendingChanges.active.targetTrackID == trackID {
                    confirmedChange = pendingChanges.active
                    remainingChanges = pendingChanges.followUp.map {
                        PendingChanges(active: $0, followUp: nil)
                    }
                } else if let followUp = pendingChanges.followUp,
                    followUp.targetTrackID == trackID
                {
                    confirmedChange = followUp
                    remainingChanges = nil
                } else {
                    return .none
                }

                guard
                    let updatedQueue = confirmedChange.applying(
                        to: state.current
                    )
                else {
                    return .none
                }
                state.current = updatedQueue
                state.pendingChanges = remainingChanges
                return .none

            case .pendingFollowUpDiscarded:
                state.pendingChanges?.followUp = nil
                return .none

            case .pendingChangesDiscarded:
                state.pendingChanges = nil
                return .none

            case .currentTrackConfirmed(let trackID):
                guard
                    let updatedQueue = state.current?.navigating(
                        to: trackID
                    )
                else {
                    return .none
                }
                state.current = updatedQueue
                return .none

            case .previousTapped:
                guard
                    let targetTrackID =
                        state.current?.previousTrackID
                else {
                    return .none
                }
                let change = QueueChange.navigation(to: targetTrackID)
                if state.pendingChanges == nil {
                    state.pendingChanges = PendingChanges(
                        active: change,
                        followUp: nil
                    )
                } else {
                    state.pendingChanges?.followUp = change
                }
                return .send(.delegate(.transitionRequested(targetTrackID)))

            case .nextTapped:
                guard
                    let targetTrackID = state.current?.nextTrackID
                else {
                    return .none
                }
                let change = QueueChange.navigation(to: targetTrackID)
                if state.pendingChanges == nil {
                    state.pendingChanges = PendingChanges(
                        active: change,
                        followUp: nil
                    )
                } else {
                    state.pendingChanges?.followUp = change
                }
                return .send(.delegate(.transitionRequested(targetTrackID)))

            case .currentTrackCompleted(let completedTrackID):
                guard
                    let targetTrackID =
                        state.current?.automaticTrackID(
                            after: completedTrackID
                        )
                else { return .none }
                let change = QueueChange.navigation(to: targetTrackID)
                if state.pendingChanges == nil {
                    state.pendingChanges = PendingChanges(
                        active: change,
                        followUp: nil
                    )
                } else {
                    state.pendingChanges?.followUp = change
                }
                return .send(.delegate(.transitionRequested(targetTrackID)))

            case .repeatTapped:
                guard let current = state.current else {
                    return .none
                }
                state.current = current.cyclingRepeatMode()
                return .none

            case .shuffleTapped:
                guard let current = state.current else {
                    return .none
                }
                switch current.shuffleMode {
                case .tracks:
                    state.current = current.disablingShuffle()
                    return .none
                case .off:
                    let shuffledTrackIDs = playbackShuffle.shuffle(
                        Array(current.tracks.ids)
                    )
                    guard
                        let shuffled = current.enablingShuffle(
                            with: shuffledTrackIDs
                        )
                    else { return .none }
                    state.current = shuffled
                    return .none
                }

            case .reset:
                state.current = nil
                state.pendingChanges = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

extension PlaybackQueueReducer.State {
    var pendingTrack: Track? {
        pendingChanges?.latest.targetTrack(in: current)
    }
}
