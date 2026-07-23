import ComposableArchitecture

extension PlaybackSkipControlsView.Model {
    /// Projects seek availability and discrete timeline actions into button models.
    ///
    /// - Parameter store: The playback store supplying seek state and receiving
    ///   backward and forward actions.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        self.init(
            controls: [
                Control(
                    id: .backward,
                    systemImage: "gobackward.15",
                    accessibilityLabel: Locs.Playback.backwardFifteenSeconds,
                    isEnabled: store.commandPolicy.allows(.seek),
                    perform: { store.send(.seekBackwardTapped) }
                ),
                Control(
                    id: .forward,
                    systemImage: "goforward.15",
                    accessibilityLabel: Locs.Playback.forwardFifteenSeconds,
                    isEnabled: store.commandPolicy.allows(.seek),
                    perform: { store.send(.seekForwardTapped) }
                ),
            ]
        )
    }
}
