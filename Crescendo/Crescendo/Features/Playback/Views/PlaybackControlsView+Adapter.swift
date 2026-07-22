import ComposableArchitecture

extension PlaybackControlsView.Model {
    /// Adapts playback state and transport actions into the controls presentation.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        let primaryAction: PrimaryAction
        if case .statusChange(let change) = store.pendingOperation {
            switch change.target {
            case .playing:
                primaryAction = .pause
            case .paused, .stopped:
                primaryAction = .play
            }
        } else {
            primaryAction = store.status == .playing ? .pause : .play
        }
        self.init(
            primaryAction: primaryAction,
            isPrimaryEnabled: store.canRequestPlayPause,
            isStopEnabled: store.canRequestStop,
            onPrimaryAction: { store.send(.playPauseTapped) },
            onStop: { store.send(.stopTapped) }
        )
    }
}
