/// The provider-confirmed transport state of the active playback session.
enum PlaybackStatus: Equatable, Sendable {
    case idle
    case playing
    case paused
    case stopped
}
