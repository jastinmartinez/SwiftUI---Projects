/// The player-confirmed transport state of the active playback session.
enum PlaybackStatus: Equatable, Sendable {
    case idle
    case waiting
    case playing
    case paused
    case stopped
}
