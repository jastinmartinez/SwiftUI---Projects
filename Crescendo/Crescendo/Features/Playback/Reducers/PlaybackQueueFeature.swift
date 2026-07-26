import ComposableArchitecture

/// Owns the playback queue contents, traversal order, current identity, and modes.
@Reducer
struct PlaybackQueueFeature {
    @ObservableState
    struct State: Equatable {
        var tracks: IdentifiedArrayOf<Track>
        var playbackOrder: PlaybackQueueOrder
        var currentTrackID: TrackID?
        var repeatMode: PlaybackRepeatMode
        var shuffleMode: PlaybackShuffleMode
    }

    enum Delegate: Equatable {
        case transitionRequested(TrackID)
    }

    enum Action: Equatable {
        case replace(
            IdentifiedArrayOf<Track>,
            startingAt: TrackID
        )
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
                guard tracks[id: startingTrackID] != nil else {
                    return .none
                }
                state.tracks = tracks
                state.playbackOrder = PlaybackQueueOrder(
                    trackIDs: Array(tracks.ids)
                )
                state.currentTrackID = startingTrackID
                state.repeatMode = .off
                state.shuffleMode = .off
                return .none

            case .currentTrackConfirmed(let trackID):
                guard state.tracks[id: trackID] != nil else { return .none }
                state.currentTrackID = trackID
                return .none

            case .previousTapped:
                guard let targetTrackID = state.previousTrackID else {
                    return .none
                }
                return .send(.delegate(.transitionRequested(targetTrackID)))

            case .nextTapped:
                guard let targetTrackID = state.nextTrackID else {
                    return .none
                }
                return .send(.delegate(.transitionRequested(targetTrackID)))

            case .currentTrackCompleted(let completedTrackID):
                guard
                    let targetTrackID = state.automaticTrackID(
                        after: completedTrackID
                    )
                else { return .none }
                return .send(.delegate(.transitionRequested(targetTrackID)))

            case .repeatTapped:
                let cycleOrder = PlaybackRepeatMode.cycleOrder
                guard
                    let index = cycleOrder.firstIndex(of: state.repeatMode)
                else { return .none }
                let nextIndex = (index + 1) % cycleOrder.count
                state.repeatMode = cycleOrder[nextIndex]
                return .none

            case .shuffleTapped:
                let canonicalTrackIDs = Array(state.tracks.ids)
                switch state.shuffleMode {
                case .tracks:
                    state.playbackOrder = PlaybackQueueOrder(
                        trackIDs: canonicalTrackIDs
                    )
                    state.shuffleMode = .off
                    return .none
                case .off:
                    let shuffledTrackIDs = playbackShuffle.shuffle(
                        canonicalTrackIDs
                    )
                    guard
                        shuffledTrackIDs.count == canonicalTrackIDs.count,
                        Set(shuffledTrackIDs) == Set(canonicalTrackIDs)
                    else { return .none }
                    state.playbackOrder = PlaybackQueueOrder(
                        trackIDs: shuffledTrackIDs
                    )
                    state.shuffleMode = .tracks
                    return .none
                }

            case .reset:
                state.tracks = []
                state.playbackOrder = PlaybackQueueOrder(trackIDs: [])
                state.currentTrackID = nil
                state.repeatMode = .off
                state.shuffleMode = .off
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

extension PlaybackQueueFeature.State {
    var currentTrack: Track? {
        guard let currentTrackID else { return nil }
        return tracks[id: currentTrackID]
    }

    var previousTrackID: TrackID? {
        guard let currentTrackID else { return nil }
        return playbackOrder.previousTrackID(before: currentTrackID)
    }

    var nextTrackID: TrackID? {
        guard let currentTrackID else { return nil }
        return playbackOrder.nextTrackID(after: currentTrackID)
    }

    var upNextTrackIDs: [TrackID] {
        guard let currentTrackID else { return [] }
        return playbackOrder.trackIDs(after: currentTrackID)
    }

    /// Returns the identity playback should advance to after a track finishes.
    ///
    /// - Parameter completedTrackID: The identity reported as finished.
    /// - Returns: The next identity under the confirmed Repeat mode, or `nil`
    ///   when the report is stale or the queue has ended.
    func automaticTrackID(after completedTrackID: TrackID) -> TrackID? {
        guard completedTrackID == currentTrackID else { return nil }
        switch repeatMode {
        case .one:
            return currentTrackID
        case .all:
            return nextTrackID ?? playbackOrder.firstTrackID
        case .off:
            return nextTrackID
        }
    }
}
