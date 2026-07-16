/// Describes the normalized lifecycle of video playback.
enum VideoPlaybackStatus: Equatable, Sendable {
    /// No video item is prepared.
    case idle
    /// The player is waiting for enough media to continue playback.
    case loading
    /// A video item is prepared but has not started playback.
    case ready
    case playing
    case paused
    case ended
}
