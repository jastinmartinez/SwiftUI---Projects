import ComposableArchitecture
import Foundation

/// Exposes provider-neutral control of the current playback position.
@DependencyClient
struct PlaybackTimelineClient: Sendable {
    var seek: @Sendable (_ time: TimeInterval) async throws -> Void
}

extension PlaybackTimelineClient: DependencyKey {
    static let liveValue = Self()
}

extension DependencyValues {
    var playbackTimeline: PlaybackTimelineClient {
        get { self[PlaybackTimelineClient.self] }
        set { self[PlaybackTimelineClient.self] = newValue }
    }
}
