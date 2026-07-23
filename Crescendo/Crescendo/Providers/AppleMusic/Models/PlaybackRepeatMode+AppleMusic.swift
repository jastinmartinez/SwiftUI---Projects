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

extension MusicPlayer.RepeatMode {
    /// Maps a provider-neutral repeat request to MusicKit queue behavior.
    init(_ playbackRepeatMode: PlaybackRepeatMode) {
        switch playbackRepeatMode {
        case .off:
            self = .none
        case .all:
            self = .all
        case .one:
            self = .one
        }
    }
}
