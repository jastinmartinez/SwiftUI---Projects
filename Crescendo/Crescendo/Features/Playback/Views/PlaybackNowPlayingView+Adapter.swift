import ComposableArchitecture

extension PlaybackNowPlayingView.Model {
    /// Adapts the selected song and playback state into the compact player presentation.
    @MainActor
    init(_ store: StoreOf<AppFeature>, song: SongSummary) {
        let isPlaying = store.playback.status == .playing

        self.init(
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            isPlaying: isPlaying,
            isPlayEnabled: store.playback.canRequestPlayPause,
            timeline: PlaybackTimelineView.Model.make(
                duration: song.duration,
                timeline: store.playback.timeline,
                supportsSeeking: store.playback.capabilities.supportsSeeking,
                strings: { elapsedTime, durationTime in
                    .localized(
                        elapsedTime: elapsedTime,
                        durationTime: durationTime
                    )
                },
                onPositionChanged: {
                    store.send(.playback(.timeline(.positionChanged($0))))
                },
                onDragEnded: {
                    store.send(.playback(.timeline(.dragEnded)))
                }
            ),
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: { store.send(.playback(.playPauseTapped)) }
        )
    }
}
