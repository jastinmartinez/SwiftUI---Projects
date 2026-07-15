import ComposableArchitecture
import Foundation

/// Exposes provider-neutral music operations to application features.
@DependencyClient
struct MusicProviderClient: Sendable {
    var currentAccess: @Sendable () async -> MusicProviderAccess = {
        .init(authorization: .notDetermined, playbackEligibility: .unknown)
    }
    var requestAccess: @Sendable () async -> MusicProviderAccess = {
        .init(authorization: .notDetermined, playbackEligibility: .unknown)
    }
    var search: @Sendable (_ query: String, _ limit: Int) async throws -> [SongSummary]
    var play: @Sendable (_ itemID: MusicItemID) async throws -> Void
    var pause: @Sendable () async throws -> Void
    var stop: @Sendable () async throws -> Void
    var seek: @Sendable (_ time: TimeInterval) async throws -> Void
    var playbackSnapshots: @Sendable () async -> AsyncStream<MusicPlaybackSnapshot> = {
        AsyncStream { $0.finish() }
    }
}

extension MusicProviderClient: DependencyKey {
    static let liveValue = MusicProviderClient()
    static let testValue = MusicProviderClient()
}

extension DependencyValues {
    var musicProvider: MusicProviderClient {
        get { self[MusicProviderClient.self] }
        set { self[MusicProviderClient.self] = newValue }
    }
}
