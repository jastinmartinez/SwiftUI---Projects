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
}
