/// A single provider-emitted playback event: an ongoing state snapshot, a
/// one-time completion event, or a one-time failure event.
enum PlaybackObservation: Equatable, Sendable {
    case snapshot(PlaybackSnapshot)
    case completed(TrackID)
    case failed(TrackID?, PlaybackFailure)
}
