/// The reducer-owned shuffle behavior of the active playback queue order.
enum PlaybackShuffleMode: Equatable, Sendable {
    case off
    case tracks
}
