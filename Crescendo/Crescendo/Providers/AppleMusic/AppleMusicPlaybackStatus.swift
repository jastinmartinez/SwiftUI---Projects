/// Mirrors Apple Music transport state without exposing MusicKit to features.
enum AppleMusicPlaybackStatus: Equatable, Sendable {
    case playing
    case paused
    case stopped
    case interrupted
}

extension MusicTransportStatus {
    /// Converts the app-owned Apple Music boundary status into normalized transport state.
    init(_ appleMusicStatus: AppleMusicPlaybackStatus) {
        switch appleMusicStatus {
        case .playing:
            self = .playing
        case .paused, .interrupted:
            self = .paused
        case .stopped:
            self = .stopped
        }
    }
}
