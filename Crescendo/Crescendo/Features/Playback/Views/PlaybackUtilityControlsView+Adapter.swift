import ComposableArchitecture

extension PlaybackUtilityControlsView.Model {
    /// Adapts secondary playback permissions and actions into presentation values.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        self.init(
            controls: [
                Control(
                    id: .restart,
                    systemImage: "arrow.counterclockwise",
                    title: Locs.Playback.restart,
                    accessibilityLabel: Locs.Playback.restart,
                    isEnabled: store.canRequestSeek,
                    perform: { store.send(.restartTapped) }
                ),
                Control(
                    id: .stop,
                    systemImage: "stop.fill",
                    title: Locs.Playback.stop,
                    accessibilityLabel: Locs.Playback.stop,
                    isEnabled: store.canRequestStop,
                    perform: { store.send(.stopTapped) }
                ),
            ]
        )
    }
}
