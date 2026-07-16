import ComposableArchitecture
import Foundation

/// Exposes AVFoundation-independent video playback operations to features.
@DependencyClient
struct VideoPlaybackClient: Sendable {
    var load: @Sendable (URL) async throws -> Void
    var pause: @Sendable () async -> Void
    var clear: @Sendable () async -> Void
    var seek: @Sendable (TimeInterval) async -> Void
    var playbackSnapshots: @Sendable () async -> AsyncStream<VideoPlaybackSnapshot> = {
        AsyncStream { $0.finish() }
    }
}

extension VideoPlaybackClient: DependencyKey {
    static let liveValue = VideoPlaybackClient()
    static let testValue = VideoPlaybackClient()
}

extension DependencyValues {
    var videoPlayback: VideoPlaybackClient {
        get { self[VideoPlaybackClient.self] }
        set { self[VideoPlaybackClient.self] = newValue }
    }
}
