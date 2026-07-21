import ComposableArchitecture

extension PlaybackControlsView.Model {
    /// Adapts playback state and transport actions into the controls presentation.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        let isPlaying = store.status == .playing
        let primaryAction: PrimaryAction = isPlaying ? .pause : .play
        let isStopEnabled: Bool
        switch store.status {
        case .playing, .paused:
            isStopEnabled = store.pendingOperation == nil
        case .idle, .stopped:
            isStopEnabled = false
        }

        self.init(
            primaryAction: primaryAction,
            isPrimaryEnabled: store.queue.currentItem != nil
                && store.capabilities.supportsEmbeddedPlayback
                && store.pendingOperation == nil,
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
