import ComposableArchitecture

extension PlaybackControlsView.Model {
    /// Projects transport and queue state into the primary playback controls.
    ///
    /// A pending status target takes precedence over confirmed status so the primary
    /// control communicates the requested action immediately.
    ///
    /// - Parameter store: The playback store supplying state and receiving actions.
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

        let repeatAccessibilityValue: String
        switch store.queue.repeatMode {
        case .off:
            repeatAccessibilityValue = Locs.Playback.Mode.off
        case .all:
            repeatAccessibilityValue = Locs.Playback.Mode.all
        case .one:
            repeatAccessibilityValue = Locs.Playback.Mode.one
        }

        self.init(
            shuffle: PlaybackModeButtonView.Model(
                systemImage: "shuffle",
                accessibilityLabel: Locs.Playback.shuffle,
                accessibilityValue: store.queue.shuffleMode == .songs
                    ? Locs.Playback.Mode.on
                    : Locs.Playback.Mode.off,
                isSelected: store.queue.shuffleMode == .songs,
                isEnabled: store.commandPolicy.allows(.shuffleMode),
                perform: { store.send(.shuffleTapped) }
            ),
            previous: PlaybackIconButtonView.Model(
                systemImage: "backward.fill",
                accessibilityLabel: Locs.Playback.previous,
                isEnabled: store.commandPolicy.allows(.previous),
                perform: { store.send(.previousTapped) }
            ),
            primary: PlaybackPrimaryButtonView.Model(
                state: primaryState,
                accessibilityLabel: primaryState == .play
                    ? Locs.Playback.play
                    : Locs.Playback.pause,
                isEnabled: store.commandPolicy.allows(.playPause),
                perform: { store.send(.playPauseTapped) }
            ),
            next: PlaybackIconButtonView.Model(
                systemImage: "forward.fill",
                accessibilityLabel: Locs.Playback.next,
                isEnabled: store.commandPolicy.allows(.next),
                perform: { store.send(.nextTapped) }
            ),
            repeatMode: PlaybackModeButtonView.Model(
                systemImage: store.queue.repeatMode == .one
                    ? "repeat.1"
                    : "repeat",
                accessibilityLabel: Locs.Playback.repeatMode,
                accessibilityValue: repeatAccessibilityValue,
                isSelected: store.queue.repeatMode != .off,
                isEnabled: store.commandPolicy.allows(.repeatMode),
                perform: { store.send(.repeatTapped) }
            )
        )
    }
}
