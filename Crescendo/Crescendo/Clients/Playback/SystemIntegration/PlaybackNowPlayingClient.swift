import ComposableArchitecture
import Foundation

/// Defines the application boundary for presenting confirmed playback on
/// operating-system media surfaces.
///
/// The client receives provider-neutral projections and does not own playback
/// state, publication policy, framework-specific keys, or artwork loading.
struct PlaybackNowPlayingClient: Sendable {
    /// Replaces the system presentation with one confirmed projection.
    var publish: @Sendable (Projection) async -> Void

    /// Removes the system presentation when no confirmed queue remains.
    var clear: @Sendable () async -> Void
}

extension PlaybackNowPlayingClient {
    /// A disposable system-presentation projection of confirmed playback.
    ///
    /// This value is not canonical playback state. It separates the current
    /// item, transport, timeline anchor, and queue context so infrastructure can
    /// translate them without inspecting reducer state.
    struct Projection: Equatable, Sendable {
        let item: Item
        let transport: Transport
        let timeline: Timeline
        let queue: QueueContext
    }
}

extension PlaybackNowPlayingClient.Projection {
    /// Describes the confirmed track presented by system media surfaces.
    struct Item: Equatable, Sendable {
        let id: TrackID
        let title: String
        let artistName: String?
        let albumTitle: String?
        let artworkURL: URL?
    }

    /// Describes confirmed transport behavior for elapsed-time extrapolation.
    struct Transport: Equatable, Sendable {
        let status: PlaybackStatus
    }

    /// Anchors confirmed playback position and duration at publication time.
    struct Timeline: Equatable, Sendable {
        let position: TimeInterval
        let duration: TimeInterval?
    }

    /// Locates the confirmed item within the confirmed playback order.
    struct QueueContext: Equatable, Sendable {
        /// The zero-based position in the confirmed playback order.
        let index: Int

        /// The number of tracks in the confirmed playback order.
        let count: Int
    }
}

extension PlaybackNowPlayingClient: DependencyKey {
    static let liveValue = Self(
        publish: { _ in
            fatalError("PlaybackNowPlayingClient.publish is not configured")
        },
        clear: {
            fatalError("PlaybackNowPlayingClient.clear is not configured")
        }
    )
}

extension DependencyValues {
    var playbackNowPlaying: PlaybackNowPlayingClient {
        get { self[PlaybackNowPlayingClient.self] }
        set { self[PlaybackNowPlayingClient.self] = newValue }
    }
}
