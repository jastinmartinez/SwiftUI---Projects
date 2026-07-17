import ComposableArchitecture

extension MusicPlaybackView.Model {
    /// Adapts reducer-owned playback state and actions into presentation values.
    @MainActor
    init(_ store: StoreOf<MusicPlaybackFeature>, providerName: String?) {
        let snapshot = store.phase.snapshot
        let statusText: String
        switch store.phase {
        case .loading:
            statusText = Locs.MusicPlayback.Status.loading
        case .failed:
            statusText = Locs.MusicPlayback.Status.failed
        case .observing:
            switch snapshot.status {
            case .idle:
                statusText = Locs.MusicPlayback.Status.idle
            case .playing:
                statusText = Locs.MusicPlayback.Status.playing
            case .paused:
                statusText = Locs.MusicPlayback.Status.paused
            case .stopped:
                statusText = Locs.MusicPlayback.Status.stopped
            }
        }

        let seek: Seek?
        if store.capabilities.supportsSeeking {
            seek = Seek(
                position: snapshot.currentTime,
                range: 0...max(1, snapshot.currentTime + 60),
                onSeek: { store.send(.seekRequested($0)) }
            )
        } else {
            seek = nil
        }

        self.init(
            title: store.selectedSong?.title ?? Locs.MusicPlayback.noSelection,
            artistName: store.selectedSong?.artistName,
            providerAttribution: providerName.map(Locs.MusicPlayback.playingFrom),
            artworkURL: store.selectedSong?.artworkURL,
            statusText: statusText,
            elapsedTimeText: snapshot.currentTime.formatted(
                .number.precision(.fractionLength(0))
            ),
            controls: MusicPlaybackControlsView.Model(store),
            eligibility: PlaybackEligibilityNoticeView.Model(store),
            seek: seek
        )
    }
}
