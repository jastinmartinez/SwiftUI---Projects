/// Defines the effective traversal order of an active playback queue.
struct PlaybackQueueOrder: Equatable, Sendable {
    let trackIDs: [TrackID]

    var firstTrackID: TrackID? {
        trackIDs.first
    }

    /// Returns the identity immediately before a known track.
    ///
    /// - Parameter trackID: The identity whose predecessor is requested.
    /// - Returns: The preceding identity, or `nil` at the beginning or when the
    ///   identity is absent.
    func previousTrackID(before trackID: TrackID) -> TrackID? {
        guard
            let index = trackIDs.firstIndex(of: trackID),
            index > trackIDs.startIndex
        else {
            return nil
        }
        return trackIDs[trackIDs.index(before: index)]
    }

    /// Returns the identity immediately after a known track.
    ///
    /// - Parameter trackID: The identity whose successor is requested.
    /// - Returns: The succeeding identity, or `nil` at the end or when the
    ///   identity is absent.
    func nextTrackID(after trackID: TrackID) -> TrackID? {
        guard let index = trackIDs.firstIndex(of: trackID) else {
            return nil
        }
        let nextIndex = trackIDs.index(after: index)
        guard nextIndex < trackIDs.endIndex else { return nil }
        return trackIDs[nextIndex]
    }

    /// Returns every identity following a known track.
    ///
    /// - Parameter trackID: The identity after which results begin.
    /// - Returns: Following identities in traversal order, or an empty array
    ///   when the identity is absent or final.
    func trackIDs(after trackID: TrackID) -> [TrackID] {
        guard let index = trackIDs.firstIndex(of: trackID) else {
            return []
        }
        let nextIndex = trackIDs.index(after: index)
        return Array(trackIDs[nextIndex...])
    }
}
