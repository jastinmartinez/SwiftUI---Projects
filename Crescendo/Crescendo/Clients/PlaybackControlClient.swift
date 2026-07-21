import ComposableArchitecture
import Foundation

/// Exposes provider-neutral playback control capabilities.
struct PlaybackControlClient: Sendable {
    var play: @Sendable (_ itemID: MusicItemID) async throws -> Void
    var resume: @Sendable () async throws -> Void
    var pause: @Sendable () async throws -> Void
    var stop: @Sendable () async throws -> Void
    var seek: @Sendable (_ time: TimeInterval) async throws -> Void
}

extension DependencyValues {
    var playbackControl: PlaybackControlClient {
        get { self[PlaybackControlClient.self] }
        set { self[PlaybackControlClient.self] = newValue }
    }
}
