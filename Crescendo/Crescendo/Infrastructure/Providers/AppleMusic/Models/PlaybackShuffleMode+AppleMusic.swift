@preconcurrency import MusicKit

extension PlaybackShuffleMode {
    /// Normalizes Apple Music's optional shuffle behavior into app-owned state.
    init(_ appleMusicShuffleMode: MusicPlayer.ShuffleMode?) {
        switch appleMusicShuffleMode {
        case nil, .some(.off):
            self = .off
        case .some(.songs):
            self = .tracks
        @unknown default:
            self = .off
        }
    }
}

extension MusicPlayer.ShuffleMode {
    /// Maps a provider-neutral shuffle request to MusicKit queue behavior.
    init(_ playbackShuffleMode: PlaybackShuffleMode) {
        switch playbackShuffleMode {
        case .off:
            self = .off
        case .tracks:
            self = .songs
        }
    }
}
