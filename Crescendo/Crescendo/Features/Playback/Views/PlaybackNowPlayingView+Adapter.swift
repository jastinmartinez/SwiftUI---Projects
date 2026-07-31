import ComposableArchitecture

extension PlaybackNowPlayingView.Model {
    /// Projects compact playback only when a confirmed queue item exists.
    ///
    /// Pending targets are intentionally ignored so compact playback never replaces
    /// confirmed metadata before the player reports the transition.
    ///
    /// - Parameter store: The playback store supplying confirmed state and actions.
    @MainActor
    init?(_ store: StoreOf<PlaybackReducer>) {
        guard let track = store.queue.current?.currentTrack else {
            return nil
        }
        self.init(store, track: track, strings: .localized)
    }

    @MainActor
    private init(
        _ store: StoreOf<PlaybackReducer>,
        track: Track,
        strings: Strings
    ) {
        let isPlaying: Bool
        if let change = store.session.pendingStatusChange {
            isPlaying = change.target == .playing
        } else {
            isPlaying = store.session.status == .playing
        }
        let policy = store.commandPolicy

        self.init(
            title: track.title,
            artistName: track.artistName ?? Locs.Common.unknownArtist,
            artworkURL: track.artworkURL,
            isPlaying: isPlaying,
            playPauseAvailability: policy.availability(for: .playPause),
            playPauseAccessibilityLabel: isPlaying
                ? strings.pause
                : strings.play,
            nextAvailability: policy.availability(for: .next),
            nextAccessibilityLabel: strings.next,
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: { store.send(.playPauseTapped) },
            onNext: { store.send(.nextTapped) }
        )
    }
}

extension PlaybackNowPlayingView.Model.Strings {
    /// Production localization wiring for compact playback.
    static let localized = Self(
        play: Locs.Playback.play,
        pause: Locs.Playback.pause,
        next: Locs.Playback.next
    )
}
