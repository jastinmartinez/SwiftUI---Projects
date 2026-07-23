import ComposableArchitecture

extension PlaybackNowPlayingView.Model {
    /// Projects a selected song and playback state into compact-player presentation.
    ///
    /// A pending status change takes precedence over confirmed status so the visible
    /// Play/Pause action responds immediately while the provider confirms the request.
    ///
    /// - Parameters:
    ///   - store: The playback store supplying state and receiving callbacks.
    ///   - song: The confirmed queue item represented by the compact player.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>, song: SongSummary) {
        let isPlaying: Bool
        if case .statusChange(let change) = store.pendingOperation {
            isPlaying = change.target == .playing
        } else {
            isPlaying = store.status == .playing
        }

        self.init(
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            isPlaying: isPlaying,
            isPlayEnabled: store.commandPolicy.allows(.playPause),
            playPauseAccessibilityLabel: isPlaying
                ? Locs.Playback.pause
                : Locs.Playback.play,
            timeline: PlaybackTimelineView.Model(store),
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: { store.send(.playPauseTapped) }
        )
    }
}
