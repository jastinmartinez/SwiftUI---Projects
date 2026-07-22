import ComposableArchitecture

extension PlaybackSkipControlsView.Model {
    /// Adapts seek permissions and skip actions into presentation values.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        self.init(
            controls: [
                Control(
                    id: .backward,
                    systemImage: "gobackward.15",
                    accessibilityLabel: Locs.Playback.backwardFifteenSeconds,
                    isEnabled: store.canRequestSeek,
                    perform: { store.send(.seekBackwardTapped) }
                ),
                Control(
                    id: .forward,
                    systemImage: "goforward.15",
                    accessibilityLabel: Locs.Playback.forwardFifteenSeconds,
                    isEnabled: store.canRequestSeek,
                    perform: { store.send(.seekForwardTapped) }
                ),
            ]
        )
    }
}
