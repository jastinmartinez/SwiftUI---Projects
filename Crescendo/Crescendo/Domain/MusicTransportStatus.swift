/// Describes the normalized lifecycle of music transport.
enum MusicTransportStatus: Equatable, Sendable {
    /// No item has been selected for playback.
    case idle
    case loading
    case playing
    case paused
    /// Playback was explicitly stopped and its position was reset.
    case stopped
    case failed
}
