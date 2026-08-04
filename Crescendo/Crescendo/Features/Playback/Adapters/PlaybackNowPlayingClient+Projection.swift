// Adds the feature-owned mapping from confirmed playback state into the
// provider-neutral value consumed by system media presentation.
//
// Keeping this initializer in the Playback feature prevents the client
// contract from depending on reducer state. Pending queue, session, timeline,
// and transition work is ignored; Apple framework translation remains in live
// infrastructure.
extension PlaybackNowPlayingClient.Projection {
    /// Creates a projection when the feature owns a confirmed queue.
    ///
    /// Initialization fails when no confirmed queue exists or its current
    /// identity is absent from the confirmed playback order.
    ///
    /// - Parameter state: Playback state containing confirmed and pending work.
    init?(playback state: PlaybackReducer.State) {
        guard let queue = state.queue.current else { return nil }
        guard
            let index = queue.playbackOrder.trackIDs.firstIndex(
                of: queue.currentTrackID
            )
        else { return nil }

        let track = queue.currentTrack
        self.init(
            item: .init(
                id: track.id,
                title: track.title,
                artistName: track.artistName,
                albumTitle: track.albumTitle,
                artworkURL: track.artworkURL
            ),
            transport: .init(status: state.session.status),
            timeline: .init(
                position: state.timeline.confirmedPosition,
                duration: state.timeline.duration
            ),
            queue: .init(
                index: index,
                count: queue.playbackOrder.trackIDs.count
            )
        )
    }
}
