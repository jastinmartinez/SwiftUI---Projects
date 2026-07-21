import Foundation

/// Provider-confirmed playback values without duplicated item metadata.
struct PlaybackSnapshot: Equatable, Sendable {
    let currentItemID: MusicItemID?
    let status: PlaybackStatus
    let currentTime: TimeInterval
    let playbackRate: PlaybackRate
    let repeatMode: PlaybackRepeatMode
    let shuffleMode: PlaybackShuffleMode
}

extension PlaybackSnapshot {
    static let idle = Self(
        currentItemID: nil,
        status: .idle,
        currentTime: 0,
        playbackRate: .normal,
        repeatMode: .off,
        shuffleMode: .off
    )
}
