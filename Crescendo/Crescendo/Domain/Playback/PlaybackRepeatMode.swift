/// The provider-confirmed repeat behavior of the active playback queue.
enum PlaybackRepeatMode: Equatable, Hashable, Sendable {
    case off
    case all
    case one
}

extension PlaybackRepeatMode {
    /// Defines the stable order used to select a provider-supported successor.
    static let cycleOrder: [Self] = [.off, .all, .one]
}
