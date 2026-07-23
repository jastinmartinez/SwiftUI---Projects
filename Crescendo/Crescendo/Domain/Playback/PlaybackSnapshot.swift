import Foundation

/// Provider-confirmed playback values without duplicated item metadata.
struct PlaybackSnapshot: Equatable, Sendable {
    let currentTrackID: TrackID?
    let status: PlaybackStatus
    let currentTime: TimeInterval
    let playbackRate: PlaybackRate
    let repeatMode: PlaybackRepeatMode
    let shuffleMode: PlaybackShuffleMode
}

extension PlaybackSnapshot {
    static let idle = Self(
        currentTrackID: nil,
        status: .idle,
        currentTime: 0,
        playbackRate: .normal,
        repeatMode: .off,
        shuffleMode: .off
    )
}
