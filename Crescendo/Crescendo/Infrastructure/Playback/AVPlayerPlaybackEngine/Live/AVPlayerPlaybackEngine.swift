@preconcurrency import AVFoundation

/// Composes focused playback clients around one shared system player.
///
/// `AppComposition` selects this concrete infrastructure implementation.
/// Reducers receive only the focused clients and never depend on this type or
/// `AVPlayer`.
@MainActor
struct AVPlayerPlaybackEngine {
    /// Loads playable URLs into the shared player.
    let item: PlaybackItemClient

    /// Controls the shared player's transport state.
    let transport: PlaybackTransportClient

    /// Controls the shared player's playback position.
    let timeline: PlaybackTimelineClient

    /// Reports player-confirmed state and events from the shared player.
    let observation: PlaybackObservationClient
}

extension AVPlayerPlaybackEngine {
    /// Creates the production client composition with a new item registry.
    ///
    /// - Parameters:
    ///   - player: The single player instance shared by every returned client.
    ///   - preparer: The component that validates and creates player items.
    /// - Returns: Focused playback clients backed by the supplied player.
    static func live(
        player: AVPlayer,
        preparer: AVPlayerItemPreparer
    ) -> Self {
        live(
            player: player,
            preparer: preparer,
            registry: AVPlayerItemRegistry()
        )
    }

    /// Creates a client composition with an explicitly supplied item registry.
    ///
    /// Supplying the registry keeps item identity shared between installation
    /// and observation while allowing deterministic infrastructure tests.
    ///
    /// - Parameters:
    ///   - player: The single player instance shared by every returned client.
    ///   - preparer: The component that validates and creates player items.
    ///   - registry: The identity registry shared by item installation and
    ///     observation.
    /// - Returns: Focused playback clients backed by the supplied player.
    static func live(
        player: AVPlayer,
        preparer: AVPlayerItemPreparer,
        registry: AVPlayerItemRegistry
    ) -> Self {
        let installer = AVPlayerItemInstaller(
            player: player,
            registry: registry
        )
        let timeline = AVPlayerTimeline(player: player)
        let transport = AVPlayerTransport(
            player: player,
            timeline: timeline
        )
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live,
            itemSeekabilityObserver: .live
        )

        return Self(
            item: .live(preparer: preparer, installer: installer),
            transport: .live(transport),
            timeline: .live(timeline),
            observation: .live(observation)
        )
    }
}
