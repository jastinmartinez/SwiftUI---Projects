import ComposableArchitecture

extension PlaybackDismissHandleView.Model {
    /// Projects expanded-player dismissal into reducer-owned presentation state.
    ///
    /// - Parameter store: The playback store receiving the dismissal request.
    @MainActor
    init(_ store: StoreOf<PlaybackReducer>) {
        self.init(
            accessibilityLabel: Locs.Playback.dismiss,
            onDismiss: { store.send(.setPlayerPresented(false)) }
        )
    }
}
