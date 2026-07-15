import Foundation

/// Captures provider-neutral playback state observed by application features.
struct MusicPlaybackSnapshot: Equatable, Sendable {
    var currentItem: SongSummary?
    var status: MusicTransportStatus
    var currentTime: TimeInterval
    var error: MusicProviderError?
}

extension MusicPlaybackSnapshot {
    /// A snapshot with no selected item, elapsed time, or failure.
    static let idle = Self(
        currentItem: nil,
        status: .idle,
        currentTime: 0,
        error: nil
    )
}
