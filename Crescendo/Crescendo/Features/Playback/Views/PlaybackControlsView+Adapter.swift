import ComposableArchitecture

extension PlaybackControlsView.Model {
    /// Adapts playback state and primary-row actions into presentation values.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        let primaryState: PlaybackPrimaryButtonView.Model.State
        if case .statusChange(let change) = store.pendingOperation {
            switch change.target {
            case .playing:
                primaryState = .pause
            case .paused, .stopped:
                primaryState = .play
            }
        } else {
            primaryState = store.status == .playing ? .pause : .play
        }

        self.init(
            previous: PlaybackIconButtonView.Model(
                systemImage: "backward.fill",
                accessibilityLabel: Locs.Playback.previous,
                isEnabled: store.canRequestQueueTransition,
                perform: { store.send(.previousTapped) }
            ),
            primary: PlaybackPrimaryButtonView.Model(
                state: primaryState,
                accessibilityLabel: primaryState == .play
                    ? Locs.Playback.play
                    : Locs.Playback.pause,
                isEnabled: store.canRequestPlayPause,
                perform: { store.send(.playPauseTapped) }
            ),
            next: PlaybackIconButtonView.Model(
                systemImage: "forward.fill",
                accessibilityLabel: Locs.Playback.next,
                isEnabled: store.canRequestQueueTransition,
                perform: { store.send(.nextTapped) }
            )
        )
    }
}
