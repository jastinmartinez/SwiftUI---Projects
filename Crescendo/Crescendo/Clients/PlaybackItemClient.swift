import ComposableArchitecture
import Foundation

/// Correlates one staged playback item with reducer-owned transition work.
struct PlaybackItemInstallation: Hashable, Sendable {
    let id: UUID
}

/// Owns transactional installation of resolved resources in shared playback.
@DependencyClient
struct PlaybackItemClient: Sendable {
    var load:
        @Sendable (
            _ resource: PlaybackResource,
            _ installation: PlaybackItemInstallation
        ) async throws -> Void
    var commit:
        @Sendable (
            _ installation: PlaybackItemInstallation
        ) async -> Void
    var rollback:
        @Sendable (
            _ installation: PlaybackItemInstallation
        ) async -> Void
}

extension PlaybackItemClient: DependencyKey {
    static let liveValue = Self()
}

extension DependencyValues {
    var playbackItem: PlaybackItemClient {
        get { self[PlaybackItemClient.self] }
        set { self[PlaybackItemClient.self] = newValue }
    }
}
