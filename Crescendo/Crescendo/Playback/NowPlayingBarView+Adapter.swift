import ComposableArchitecture

extension NowPlayingBarView.Model {
    /// Adapts the selected song and playback state into the compact player presentation.
    @MainActor
    init(_ store: StoreOf<AppFeature>, song: SongSummary) {
        self.init(
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            isPlaying: store.musicPlayback.phase.snapshot.status == .playing,
            onOpenPlayer: { store.send(.setPlayerPresented(true)) }
        )
    }
}
