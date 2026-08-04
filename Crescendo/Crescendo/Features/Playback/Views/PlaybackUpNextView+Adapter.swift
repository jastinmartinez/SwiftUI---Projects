import ComposableArchitecture

extension PlaybackUpNextView.Model {
    /// Resolves the queue-owned traversal order into stateless row models.
    ///
    /// Initialization fails when no confirmed tracks remain after the current item.
    /// The adapter preserves `upNextTrackIDs` order and does not derive queue policy.
    ///
    /// - Parameters:
    ///   - store: The playback store supplying confirmed queue state.
    ///   - title: The localized section title.
    @MainActor
    init?(
        _ store: StoreOf<PlaybackReducer>,
        title: String
    ) {
        let tracks = store.queue.current?.upNextTracks ?? []
        guard !tracks.isEmpty else { return nil }

        self.init(
            title: title,
            tracks: tracks.map {
                TrackRowView.Model(
                    $0,
                    accessory: .none,
                    showsDuration: true
                )
            }
        )
    }

    /// Resolves Up Next using production localization.
    ///
    /// Initialization fails when no confirmed tracks remain after the current
    /// item.
    ///
    /// - Parameter store: The playback store supplying confirmed queue state.
    @MainActor
    init?(_ store: StoreOf<PlaybackReducer>) {
        self.init(store, title: Locs.Playback.upNext)
    }
}
