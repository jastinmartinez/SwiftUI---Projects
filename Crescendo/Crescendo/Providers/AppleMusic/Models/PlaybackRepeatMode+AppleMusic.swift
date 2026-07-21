@preconcurrency import MusicKit

extension PlaybackRepeatMode {
    /// Normalizes Apple Music's optional repeat behavior into app-owned state.
    init(_ appleMusicRepeatMode: MusicPlayer.RepeatMode?) {
        switch appleMusicRepeatMode {
        case nil, .some(.none):
            self = .off
        case .some(.all):
            self = .all
        case .some(.one):
            self = .one
        @unknown default:
            self = .off
        }
    }
}
