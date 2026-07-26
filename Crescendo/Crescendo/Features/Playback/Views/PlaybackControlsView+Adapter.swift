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
        self.init(store, strings: .localized)
    }

    /// Projects controls using explicitly supplied localized labels and values.
    ///
    /// - Parameters:
    ///   - store: The playback store supplying state and receiving actions.
    ///   - strings: Localized presentation copy for the control row.
    @MainActor
    init(
        _ store: StoreOf<PlaybackFeature>,
        strings: Strings
    ) {
        let primaryState: PlaybackPrimaryButtonView.Model.State
        if let change = store.pendingStatusChange {
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
            repeatAccessibilityValue = strings.modeOff
        case .all:
            repeatAccessibilityValue = strings.modeAll
        case .one:
            repeatAccessibilityValue = strings.modeOne
        }

        self.init(
            shuffle: PlaybackModeButtonView.Model(
                systemImage: "shuffle",
                accessibilityLabel: strings.shuffle,
                accessibilityValue: store.queue.shuffleMode == .tracks
                    ? strings.modeOn
                    : strings.modeOff,
                isSelected: store.queue.shuffleMode == .tracks,
                isEnabled: store.canRequestShuffle,
                perform: { store.send(.shuffleTapped) }
            ),
            previous: PlaybackIconButtonView.Model(
                systemImage: "backward.fill",
                accessibilityLabel: strings.previous,
                isEnabled: store.canRequestPrevious,
                perform: { store.send(.previousTapped) }
            ),
            primary: PlaybackPrimaryButtonView.Model(
                state: primaryState,
                accessibilityLabel: primaryState == .play
                    ? strings.play
                    : strings.pause,
                isEnabled: store.canRequestPlayPause,
                perform: { store.send(.playPauseTapped) }
            ),
            next: PlaybackIconButtonView.Model(
                systemImage: "forward.fill",
                accessibilityLabel: strings.next,
                isEnabled: store.canRequestNext,
                perform: { store.send(.nextTapped) }
            ),
            repeatMode: PlaybackModeButtonView.Model(
                systemImage: store.queue.repeatMode == .one
                    ? "repeat.1"
                    : "repeat",
                accessibilityLabel: strings.repeatMode,
                accessibilityValue: repeatAccessibilityValue,
                isSelected: store.queue.repeatMode != .off,
                isEnabled: store.canRequestRepeat,
                perform: { store.send(.repeatTapped) }
            )
        )
    }
}

extension PlaybackControlsView.Model.Strings {
    /// Production localization wiring for the primary playback controls.
    static let localized = Self(
        play: Locs.Playback.play,
        pause: Locs.Playback.pause,
        previous: Locs.Playback.previous,
        next: Locs.Playback.next,
        shuffle: Locs.Playback.shuffle,
        repeatMode: Locs.Playback.repeatMode,
        modeOff: Locs.Playback.Mode.off,
        modeOn: Locs.Playback.Mode.on,
        modeAll: Locs.Playback.Mode.all,
        modeOne: Locs.Playback.Mode.one
    )
}
