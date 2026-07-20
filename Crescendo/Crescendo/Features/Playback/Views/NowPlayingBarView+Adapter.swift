import ComposableArchitecture

extension NowPlayingBarView.Model {
    /// Adapts the selected song and playback state into the compact player presentation.
    @MainActor
    init(_ store: StoreOf<AppFeature>, song: SongSummary) {
        let snapshot = store.musicPlayback.phase.snapshot
        let isPlaying = snapshot.status == .playing

        self.init(
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            isPlaying: isPlaying,
            isPlayEnabled: store.musicPlayback.canPlaySelectedSong,
            timeline: MusicPlaybackTimelineView.Model.make(
                duration: song.duration,
                snapshot: snapshot,
                timeline: store.musicPlayback.timeline,
                supportsSeeking: store.musicPlayback.capabilities.supportsSeeking,
                strings: { elapsedTime, durationTime in
                    .localized(
                        elapsedTime: elapsedTime,
                        durationTime: durationTime
                    )
                },
                onPositionChanged: {
                    store.send(.musicPlayback(.timeline(.positionChanged($0))))
                },
                onDragEnded: {
                    store.send(.musicPlayback(.timeline(.dragEnded)))
                }
            ),
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: {
                store.send(.musicPlayback(isPlaying ? .pauseTapped : .playTapped))
            }
        )
    }
}
