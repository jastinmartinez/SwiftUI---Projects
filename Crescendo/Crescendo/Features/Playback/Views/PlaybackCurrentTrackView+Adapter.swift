import ComposableArchitecture

extension PlaybackCurrentTrackView.Model {
    /// Projects current-track identity and status without reading timeline or
    /// queue-list presentation.
    ///
    /// - Parameter store: The playback store supplying track and status state.
    @MainActor
    init(_ store: StoreOf<PlaybackReducer>) {
        self.init(store, strings: .localized)
    }

    /// Projects current-track presentation with explicit transient-state copy.
    ///
    /// - Parameters:
    ///   - store: The playback store supplying track and status state.
    ///   - strings: Localized strings for transient playback states.
    @MainActor
    init(
        _ store: StoreOf<PlaybackReducer>,
        strings: Strings
    ) {
        let statusText: String
        if let change = store.session.pendingStatusChange {
            switch change.target {
            case .playing:
                statusText = Locs.Playback.Status.playing
            case .paused:
                statusText = Locs.Playback.Status.paused
            case .stopped:
                statusText = Locs.Playback.Status.stopped
            }
        } else if store.transition != nil {
            statusText = strings.loading
        } else if let failure = store.failureNotice?.failure {
            statusText =
                switch failure {
                case .resourceUnavailable:
                    strings.resourceUnavailable
                case .unsupportedResource:
                    strings.unsupportedResource
                case .preparationFailed:
                    strings.preparationFailed
                case .playbackFailed:
                    strings.playbackFailed
                }
        } else {
            switch store.session.status {
            case .idle:
                statusText = Locs.Playback.Status.idle
            case .waiting:
                statusText = Locs.Playback.Status.waiting
            case .playing:
                statusText = Locs.Playback.Status.playing
            case .paused:
                statusText = Locs.Playback.Status.paused
            case .stopped:
                statusText = Locs.Playback.Status.stopped
            }
        }

        let confirmedTrack = store.queue.current?.currentTrack
        let pendingTrack = store.queue.pendingTrack
        let displayedTrack = confirmedTrack ?? pendingTrack

        self.init(
            artworkURL: displayedTrack?.artworkURL,
            metadata: PlaybackMetadataView.Model(
                title: displayedTrack?.title ?? Locs.Playback.noSelection,
                artistName: displayedTrack.map {
                    $0.artistName ?? Locs.Common.unknownArtist
                },
                statusText: statusText
            )
        )
    }
}

extension PlaybackCurrentTrackView.Model.Strings {
    /// Production localization wiring for transient playback presentation.
    static let localized = Self(
        loading: Locs.Playback.Status.loading,
        resourceUnavailable: Locs.Playback.Failure.resourceUnavailable,
        unsupportedResource: Locs.Playback.Failure.unsupportedResource,
        preparationFailed: Locs.Playback.Failure.preparationFailed,
        playbackFailed: Locs.Playback.Failure.playbackFailed
    )
}
