import ComposableArchitecture

extension PlaybackControlsView.Model {
    /// Adapts playback state and transport actions into the controls presentation.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        let isPlaying = store.status == .playing
        let primaryAction: PrimaryAction = isPlaying ? .pause : .play
        self.init(
            primaryAction: primaryAction,
            isPrimaryEnabled: store.canRequestPlayPause,
            isStopEnabled: store.canRequestStop,
            onPrimaryAction: { store.send(.playPauseTapped) },
            onStop: { store.send(.stopTapped) }
        )
    }
}
