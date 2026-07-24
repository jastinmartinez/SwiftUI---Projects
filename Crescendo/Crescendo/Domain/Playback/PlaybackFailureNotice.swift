/// A one-time playback failure associated with the affected track.
struct PlaybackFailureNotice: Equatable, Sendable {
    let trackID: TrackID
    let failure: PlaybackFailure
}
