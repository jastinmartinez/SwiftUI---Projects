import Foundation

/// Captures AVFoundation-independent video playback state.
struct VideoPlaybackSnapshot: Equatable, Sendable {
    var status: VideoPlaybackStatus
    var currentTime: TimeInterval
}

extension VideoPlaybackSnapshot {
    /// A snapshot with no prepared item or elapsed time.
    static let idle = Self(
        status: .idle,
        currentTime: 0
    )
}
