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
        _ store: StoreOf<PlaybackFeature>,
        title: String
    ) {
        let tracks = store.queue.upNextTrackIDs.compactMap {
            store.queue.tracks[id: $0]
        }
        guard !tracks.isEmpty else { return nil }

        self.init(
            title: title,
            tracks: tracks.map {
                TrackRowView.Model($0, accessory: .none)
            }
        )
    }

    /// Resolves Up Next using production localization.
    ///
    /// - Parameter store: The playback store supplying confirmed queue state.
    @MainActor
    init?(_ store: StoreOf<PlaybackFeature>) {
        self.init(store, title: Locs.Playback.upNext)
    }
}
