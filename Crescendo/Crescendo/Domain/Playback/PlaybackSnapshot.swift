import Foundation

/// Player-confirmed identity, transport state, and timeline values.
struct PlaybackSnapshot: Equatable, Sendable {
    let currentTrackID: TrackID?
    let status: PlaybackStatus
    let position: TimeInterval
    let duration: TimeInterval?
}

extension PlaybackSnapshot {
    static let idle = Self(
        currentTrackID: nil,
        status: .idle,
        position: 0,
        duration: nil
    )
}
