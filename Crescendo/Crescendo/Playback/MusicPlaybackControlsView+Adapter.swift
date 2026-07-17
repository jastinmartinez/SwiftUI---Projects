import ComposableArchitecture

extension MusicPlaybackControlsView.Model {
    /// Adapts playback state and transport actions into the controls presentation.
    @MainActor
    init(_ store: StoreOf<MusicPlaybackFeature>) {
        let isPlaying = store.phase.snapshot.status == .playing
        let primaryAction: PrimaryAction = isPlaying ? .pause : .play
        let isStopEnabled: Bool
        switch store.phase.snapshot.status {
        case .playing, .paused:
            isStopEnabled = true
        case .idle, .stopped:
            isStopEnabled = false
        }

        self.init(
            primaryAction: primaryAction,
            isPrimaryEnabled: isPlaying || store.canPlaySelectedSong,
            isStopEnabled: isStopEnabled,
            onPrimaryAction: {
                switch primaryAction {
                case .play:
                    store.send(.playTapped)
                case .pause:
                    store.send(.pauseTapped)
                }
            },
            onStop: { store.send(.stopTapped) }
        )
    }
}
