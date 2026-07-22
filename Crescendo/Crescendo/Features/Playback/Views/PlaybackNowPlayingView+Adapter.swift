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
            timeline: PlaybackTimelineView.Model(
                store,
                showsControls: false
            ),
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: { store.send(.playPauseTapped) }
        )
    }
}
