/// The reducer-owned repeat behavior applied when a track finishes playing.
enum PlaybackRepeatMode: Equatable, Hashable, Sendable {
    case off
    case all
    case one
}

extension PlaybackRepeatMode {
    /// Defines the stable order the reducer cycles through on each Repeat tap.
    static let cycleOrder: [Self] = [.off, .all, .one]
}
