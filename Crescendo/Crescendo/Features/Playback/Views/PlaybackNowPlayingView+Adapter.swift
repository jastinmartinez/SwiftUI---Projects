import ComposableArchitecture

extension PlaybackNowPlayingView.Model {
    /// Projects compact playback only when a confirmed queue item exists.
    ///
    /// Pending targets are intentionally ignored so compact playback never replaces
    /// confirmed metadata before the player reports the transition.
    ///
    /// - Parameter store: The playback store supplying confirmed state and actions.
    @MainActor
    init?(_ store: StoreOf<PlaybackFeature>) {
        guard let track = store.queue.currentTrack else { return nil }
        self.init(store, track: track, strings: .localized)
    }

    @MainActor
    private init(
        _ store: StoreOf<PlaybackFeature>,
        track: Track,
        strings: Strings
    ) {
        let isPlaying: Bool
        if let change = store.pendingStatusChange {
            isPlaying = change.target == .playing
        } else {
            isPlaying = store.status == .playing
        }

        self.init(
            title: track.title,
            artistName: track.artistName,
            artworkURL: track.artworkURL,
            isPlaying: isPlaying,
            isPlayPauseEnabled: store.canRequestPlayPause,
            playPauseAccessibilityLabel: isPlaying
                ? strings.pause
                : strings.play,
            timeline: PlaybackTimelineView.Model(store),
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: { store.send(.playPauseTapped) }
        )
    }
}

extension PlaybackNowPlayingView.Model.Strings {
    /// Production localization wiring for compact playback.
    static let localized = Self(
        play: Locs.Playback.play,
        pause: Locs.Playback.pause
    )
}
