import IdentifiedCollections

/// A validated, non-empty playback queue.
///
/// Absence is represented by an optional `PlaybackQueue` at the feature
/// boundary. Every value of this type has one current track and a traversal
/// order containing every known track exactly once.
struct PlaybackQueue: Equatable, Sendable {
    let tracks: IdentifiedArrayOf<Track>
    let playbackOrder: PlaybackQueueOrder
    let currentTrackID: TrackID
    let repeatMode: PlaybackRepeatMode
    let shuffleMode: PlaybackShuffleMode

    /// Creates a queue after validating its current identity and traversal
    /// order.
    ///
    /// - Parameters:
    ///   - tracks: The tracks owned by the queue.
    ///   - playbackOrder: The effective traversal order.
    ///   - currentTrackID: The currently confirmed track identity.
    ///   - repeatMode: The confirmed Repeat mode.
    ///   - shuffleMode: The confirmed Shuffle mode.
    init?(
        tracks: IdentifiedArrayOf<Track>,
        playbackOrder: PlaybackQueueOrder,
        currentTrackID: TrackID,
        repeatMode: PlaybackRepeatMode,
        shuffleMode: PlaybackShuffleMode
    ) {
        let knownTrackIDs = Array(tracks.ids)
        let orderedTrackIDs = playbackOrder.trackIDs
        guard tracks[id: currentTrackID] != nil,
            orderedTrackIDs.count == knownTrackIDs.count,
            Set(orderedTrackIDs) == Set(knownTrackIDs)
        else {
            return nil
        }
        self.init(
            validatedTracks: tracks,
            playbackOrder: playbackOrder,
            currentTrackID: currentTrackID,
            repeatMode: repeatMode,
            shuffleMode: shuffleMode
        )
    }

    /// Creates a canonical replacement queue with Repeat and Shuffle disabled.
    ///
    /// - Parameters:
    ///   - tracks: The replacement tracks in source order.
    ///   - currentTrackID: The track that becomes current.
    init?(
        tracks: IdentifiedArrayOf<Track>,
        startingAt currentTrackID: TrackID
    ) {
        self.init(
            tracks: tracks,
            playbackOrder: PlaybackQueueOrder(
                trackIDs: Array(tracks.ids)
            ),
            currentTrackID: currentTrackID,
            repeatMode: .off,
            shuffleMode: .off
        )
    }

    private init(
        validatedTracks tracks: IdentifiedArrayOf<Track>,
        playbackOrder: PlaybackQueueOrder,
        currentTrackID: TrackID,
        repeatMode: PlaybackRepeatMode,
        shuffleMode: PlaybackShuffleMode
    ) {
        self.tracks = tracks
        self.playbackOrder = playbackOrder
        self.currentTrackID = currentTrackID
        self.repeatMode = repeatMode
        self.shuffleMode = shuffleMode
    }

    var currentTrack: Track {
        guard let track = tracks[id: currentTrackID] else {
            preconditionFailure(
                "PlaybackQueue current identity must resolve to a track"
            )
        }
        return track
    }

    var previousTrackID: TrackID? {
        playbackOrder.previousTrackID(before: currentTrackID)
    }

    var nextTrackID: TrackID? {
        playbackOrder.nextTrackID(after: currentTrackID)
    }

    var upNextTracks: [Track] {
        playbackOrder.trackIDs(after: currentTrackID).compactMap {
            tracks[id: $0]
        }
    }

    /// Returns a queue with the requested known track as its current identity.
    ///
    /// - Parameter trackID: The identity that should become current.
    /// - Returns: The updated queue, or `nil` when the identity is unknown.
    func navigating(to trackID: TrackID) -> Self? {
        guard tracks[id: trackID] != nil else { return nil }
        return Self(
            validatedTracks: tracks,
            playbackOrder: playbackOrder,
            currentTrackID: trackID,
            repeatMode: repeatMode,
            shuffleMode: shuffleMode
        )
    }

    /// Returns a queue with Repeat advanced through Off, All, and One.
    func cyclingRepeatMode() -> Self {
        let cycleOrder = PlaybackRepeatMode.cycleOrder
        guard let index = cycleOrder.firstIndex(of: repeatMode) else {
            return self
        }
        let nextIndex = (index + 1) % cycleOrder.count
        return Self(
            validatedTracks: tracks,
            playbackOrder: playbackOrder,
            currentTrackID: currentTrackID,
            repeatMode: cycleOrder[nextIndex],
            shuffleMode: shuffleMode
        )
    }

    /// Returns a queue using an exact permutation of its known tracks.
    ///
    /// - Parameter trackIDs: The proposed shuffled traversal order.
    /// - Returns: The shuffled queue, or `nil` when the order is invalid.
    func enablingShuffle(with trackIDs: [TrackID]) -> Self? {
        Self(
            tracks: tracks,
            playbackOrder: PlaybackQueueOrder(trackIDs: trackIDs),
            currentTrackID: currentTrackID,
            repeatMode: repeatMode,
            shuffleMode: .tracks
        )
    }

    /// Returns a queue restored to source traversal order with Shuffle off.
    func disablingShuffle() -> Self {
        Self(
            validatedTracks: tracks,
            playbackOrder: PlaybackQueueOrder(
                trackIDs: Array(tracks.ids)
            ),
            currentTrackID: currentTrackID,
            repeatMode: repeatMode,
            shuffleMode: .off
        )
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
