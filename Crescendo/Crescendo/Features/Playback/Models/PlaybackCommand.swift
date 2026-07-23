/// A user-initiated playback operation whose validity depends on domain state.
enum PlaybackCommand: CaseIterable, Equatable, Sendable {
    case playPause
    case stop
    case seek
    case previous
    case next
    case repeatMode
    case shuffleMode
}
