import ComposableArchitecture

extension NowPlayingBarView.Model {
    /// Adapts the selected song and playback state into the compact player presentation.
    @MainActor
    init(_ store: StoreOf<AppFeature>, song: SongSummary) {
        let snapshot = store.musicPlayback.phase.snapshot
        let duration = song.duration
        let progress: Double? = duration.flatMap { duration in
            guard duration > 0 else { return nil }
            return min(max(snapshot.currentTime / duration, 0), 1)
        }
        let isPlaying = snapshot.status == .playing

        self.init(
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            isPlaying: isPlaying,
            isPlayEnabled: store.musicPlayback.canPlaySelectedSong,
            elapsedTimeText: snapshot.currentTime.musicDurationText,
            durationText: duration?.musicDurationText,
            progress: progress,
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: {
                store.send(.musicPlayback(isPlaying ? .pauseTapped : .playTapped))
            }
        )
    }
}
