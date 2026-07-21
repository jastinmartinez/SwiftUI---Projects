import ComposableArchitecture

extension PlaybackNowPlayingView.Model {
    /// Adapts the selected song and playback state into the compact player presentation.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>, song: SongSummary) {
        let isPlaying = store.status == .playing

        self.init(
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            isPlaying: isPlaying,
            isPlayEnabled: store.canRequestPlayPause,
            timeline: PlaybackTimelineView.Model.make(
                duration: song.duration,
                timeline: store.timeline,
                supportsSeeking: store.capabilities.supportsSeeking,
                strings: { elapsedTime, durationTime in
                    .localized(
                        elapsedTime: elapsedTime,
                        durationTime: durationTime
                    )
                },
                onPositionChanged: {
                    store.send(.timeline(.positionChanged($0)))
                },
                onDragEnded: {
                    store.send(.timeline(.dragEnded))
                }
            ),
            onOpenPlayer: { store.send(.setPlayerPresented(true)) },
            onTogglePlayPause: { store.send(.playPauseTapped) }
        )
    }
}
