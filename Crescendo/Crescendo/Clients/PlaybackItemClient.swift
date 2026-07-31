import ComposableArchitecture
import Foundation

/// Correlates one staged playback item with reducer-owned transition work.
struct PlaybackItemInstallation: Hashable, Sendable {
    let id: UUID
}

/// Owns transactional installation of playable URLs in shared playback.
@DependencyClient
struct PlaybackItemClient: Sendable {
    /// Prepares and stages `playbackURL` under the correlated installation.
    ///
    /// If this operation throws, it leaves no staged mutation for
    /// `installation`; callers can continue relying on the previously committed
    /// playback item.
    var load: @Sendable (
        _ trackID: TrackID,
        _ playbackURL: URL,
        _ installation: PlaybackItemInstallation
    ) async throws -> Void
    var commit: @Sendable (_ installation: PlaybackItemInstallation) async -> Void
    var rollback: @Sendable (_ installation: PlaybackItemInstallation) async -> Void
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
