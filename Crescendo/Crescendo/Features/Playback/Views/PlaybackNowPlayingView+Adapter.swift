import ComposableArchitecture

extension PlaybackNowPlayingView.Model {
    /// Adapts the selected song and playback state into the compact player presentation.
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
            isPlayEnabled: store.canRequestPlayPause,
            playPauseAccessibilityLabel: isPlaying
                ? Locs.Playback.pause
                : Locs.Playback.play,
            timeline: PlaybackTimelineView.Model(store),
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: { store.send(.playPauseTapped) }
        )
    }
}
