import ComposableArchitecture

extension NowPlayingBarView.Model {
    /// Adapts the selected song and playback state into the compact player presentation.
    @MainActor
    init(_ store: StoreOf<AppFeature>, song: SongSummary) {
        let isPlaying = store.musicPlayback.phase.snapshot.status == .playing
        self.init(
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            isPlaying: isPlaying,
            isPlayEnabled: store.musicPlayback.canPlaySelectedSong,
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: {
                store.send(.musicPlayback(Self.toggleAction(isPlaying: isPlaying)))
            }
        )
    }

    /// Chooses the transport action the bar's toggle sends for the current state.
    static func toggleAction(isPlaying: Bool) -> MusicPlaybackFeature.Action {
        isPlaying ? .pauseTapped : .playTapped
    }
}
