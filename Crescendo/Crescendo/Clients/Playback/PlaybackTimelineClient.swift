import ComposableArchitecture
import Foundation

/// Exposes provider-neutral control of the current playback position.
struct PlaybackTimelineClient: Sendable {
    var seek: @Sendable (_ time: TimeInterval) async -> PlaybackOperationOutcome
}

extension PlaybackTimelineClient: DependencyKey {
    static let liveValue = Self(
        seek: { _ in
            fatalError("PlaybackTimelineClient.seek is not configured")
        }
    )
}

extension DependencyValues {
    var playbackTimeline: PlaybackTimelineClient {
        get { self[PlaybackTimelineClient.self] }
        set { self[PlaybackTimelineClient.self] = newValue }
    }
}
