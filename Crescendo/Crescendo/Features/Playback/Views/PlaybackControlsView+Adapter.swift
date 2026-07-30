import ComposableArchitecture

extension PlaybackControlsView.Model {
    /// Projects transport and queue state into the primary playback controls.
    ///
    /// A pending status target takes precedence over confirmed status so the primary
    /// control communicates the requested action immediately.
    ///
    /// - Parameter store: The playback store supplying state and receiving actions.
    @MainActor
    init(_ store: StoreOf<PlaybackReducer>) {
        self.init(store, strings: .localized)
    }

    /// Projects controls using explicitly supplied localized labels and values.
    ///
    /// - Parameters:
    ///   - store: The playback store supplying state and receiving actions.
    ///   - strings: Localized presentation copy for the control row.
    @MainActor
    init(
        _ store: StoreOf<PlaybackReducer>,
        strings: Strings
    ) {
        let policy = store.commandPolicy
        let primaryState: PlaybackPrimaryButtonView.Model.State
        if let change = store.session.pendingStatusChange {
            switch change.target {
            case .playing:
                primaryState = .pause
            case .paused, .stopped:
                primaryState = .play
            }
        } else {
            primaryState =
                store.session.status == .playing ? .pause : .play
        }

        let repeatMode = store.queue.current?.repeatMode ?? .off
        let shuffleMode = store.queue.current?.shuffleMode ?? .off
        let repeatAccessibilityValue: String
        switch repeatMode {
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
                accessibilityValue: shuffleMode == .tracks
                    ? strings.modeOn
                    : strings.modeOff,
                isSelected: shuffleMode == .tracks,
                availability: policy.availability(for: .shuffleMode),
                perform: { store.send(.shuffleTapped) }
            ),
            previous: PlaybackIconButtonView.Model(
                systemImage: "backward.fill",
                accessibilityLabel: strings.previous,
                availability: policy.availability(for: .previous),
                perform: { store.send(.previousTapped) }
            ),
            primary: PlaybackPrimaryButtonView.Model(
                state: primaryState,
                accessibilityLabel: primaryState == .play
                    ? strings.play
                    : strings.pause,
                availability: policy.availability(for: .playPause),
                perform: { store.send(.playPauseTapped) }
            ),
            next: PlaybackIconButtonView.Model(
                systemImage: "forward.fill",
                accessibilityLabel: strings.next,
                availability: policy.availability(for: .next),
                perform: { store.send(.nextTapped) }
            ),
            repeatMode: PlaybackModeButtonView.Model(
                systemImage: repeatMode == .one
                    ? "repeat.1"
                    : "repeat",
                accessibilityLabel: strings.repeatMode,
                accessibilityValue: repeatAccessibilityValue,
                isSelected: repeatMode != .off,
                availability: policy.availability(for: .repeatMode),
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
