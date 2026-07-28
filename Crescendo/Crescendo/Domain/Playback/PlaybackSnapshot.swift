import Foundation

/// Player-confirmed identity, transport state, timeline, and seekability values.
struct PlaybackSnapshot: Equatable, Sendable {
    let currentTrackID: TrackID?
    let status: PlaybackStatus
    let position: TimeInterval
    let duration: TimeInterval?
    let isSeekable: Bool
}

extension PlaybackSnapshot {
    static let idle = Self(
        currentTrackID: nil,
        status: .idle,
        position: 0,
        duration: nil,
        isSeekable: false
    )
}
