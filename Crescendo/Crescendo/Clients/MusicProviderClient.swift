import ComposableArchitecture
import Foundation

/// Exposes provider-neutral music operations to application features.
struct MusicProviderClient: Sendable {
    var currentAccess: @Sendable () async -> MusicProviderAccess
    var requestAccess: @Sendable () async -> MusicProviderAccess
    var search: @Sendable (_ query: String, _ limit: Int) async throws -> [SongSummary]
    var play: @Sendable (_ itemID: MusicItemID) async throws -> Void
    var resume: @Sendable () async throws -> Void
    var pause: @Sendable () async throws -> Void
    var stop: @Sendable () async throws -> Void
    var seek: @Sendable (_ time: TimeInterval) async throws -> Void
    var playbackSnapshots: @Sendable () async -> AsyncStream<MusicPlaybackSnapshot>
}

extension DependencyValues {
    var musicProvider: MusicProviderClient {
        get { self[MusicProviderClient.self] }
        set { self[MusicProviderClient.self] = newValue }
    }
}
