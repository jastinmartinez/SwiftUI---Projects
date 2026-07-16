/// Describes provider-neutral music playback state.
enum MusicPlaybackStatus: Equatable, Sendable {
    /// No item has been selected for playback.
    case idle
    case playing
    case paused
    /// Playback was explicitly stopped and its position was reset.
    case stopped
}
