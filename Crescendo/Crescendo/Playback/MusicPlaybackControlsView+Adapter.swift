import ComposableArchitecture

extension MusicPlaybackControlsView.Model {
    /// Adapts playback state and transport actions into the controls presentation.
    @MainActor
    init(_ store: StoreOf<MusicPlaybackFeature>) {
        self.init(
            canPlay: store.canPlaySelectedSong,
            onPlay: { store.send(.playTapped) },
            onPause: { store.send(.pauseTapped) },
            onStop: { store.send(.stopTapped) }
        )
    }

    /// Maps the playback phase into localized presentation copy.
    static func localizedStatus(for phase: MusicPlaybackFeature.Phase) -> String {
        switch phase {
        case .loading:
            Locs.MusicPlayback.Status.loading
        case .failed:
            Locs.MusicPlayback.Status.failed
        case .observing(let snapshot):
            switch snapshot.status {
            case .idle:
                Locs.MusicPlayback.Status.idle
            case .playing:
                Locs.MusicPlayback.Status.playing
            case .paused:
                Locs.MusicPlayback.Status.paused
            case .stopped:
                Locs.MusicPlayback.Status.stopped
            }
        }
    }
}
