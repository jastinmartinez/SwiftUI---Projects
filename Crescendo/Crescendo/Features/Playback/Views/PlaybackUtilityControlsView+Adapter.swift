import ComposableArchitecture

extension PlaybackUtilityControlsView.Model {
    /// Projects secondary playback capabilities into ordered utility-control models.
    ///
    /// - Parameter store: The playback store supplying availability and receiving
    ///   Restart and Stop actions.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        self.init(
            controls: [
                Control(
                    id: .restart,
                    systemImage: "arrow.counterclockwise",
                    title: Locs.Playback.restart,
                    accessibilityLabel: Locs.Playback.restart,
                    isEnabled: store.commandPolicy.allows(.seek),
                    perform: { store.send(.restartTapped) }
                ),
                Control(
                    id: .stop,
                    systemImage: "stop.fill",
                    title: Locs.Playback.stop,
                    accessibilityLabel: Locs.Playback.stop,
                    isEnabled: store.commandPolicy.allows(.stop),
                    perform: { store.send(.stopTapped) }
                ),
            ]
        )
    }
}
