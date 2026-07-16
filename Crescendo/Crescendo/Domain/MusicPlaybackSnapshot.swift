import Foundation

/// Captures provider-neutral playback state observed by application features.
struct MusicPlaybackSnapshot: Equatable, Sendable {
    var currentItem: SongSummary?
    var status: MusicPlaybackStatus
    var currentTime: TimeInterval
}

extension MusicPlaybackSnapshot {
    /// A snapshot with no selected item or elapsed time.
    static let idle = Self(
        currentItem: nil,
        status: .idle,
        currentTime: 0
    )
}
