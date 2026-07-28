import ComposableArchitecture
import Foundation

extension PlaybackView.Model {
    /// Projects reducer-owned playback state into the expanded-player presentation.
    ///
    /// Pending transport targets take precedence over confirmed status, while
    /// timeline-dependent sections are omitted when no valid duration exists.
    ///
    /// - Parameter store: The playback store supplying domain state and receiving
    ///   callbacks.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>) {
        self.init(
            store,
            strings: .localized
        )
    }

    /// Projects playback state using an explicitly supplied localization bundle.
    ///
    /// This initializer keeps failure wording outside reducer state and makes the
    /// projection independently testable.
    ///
    /// - Parameters:
    ///   - store: The playback store supplying domain state and receiving callbacks.
    ///   - strings: Localized transient-state strings used by the projection.
    @MainActor
    init(
        _ store: StoreOf<PlaybackFeature>,
        strings: Strings
    ) {
        let statusText: String
        if let change = store.pendingStatusChange {
            switch change.target {
            case .playing:
                statusText = Locs.Playback.Status.playing
            case .paused:
                statusText = Locs.Playback.Status.paused
            case .stopped:
                statusText = Locs.Playback.Status.stopped
            }
        } else if store.pendingPlaybackTransition != nil {
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
            switch store.status {
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

        let confirmedTrack = store.queue.currentTrack
        let pendingTrack = store.pendingPlaybackTransition.flatMap {
            $0.queue[id: $0.targetTrackID]
        }
        let displayedTrack = confirmedTrack ?? pendingTrack

        let timeline = PlaybackTimelineView.Model(store)

        self.init(
            artworkURL: displayedTrack?.artworkURL,
            metadata: PlaybackMetadataView.Model(
                title: displayedTrack?.title ?? Locs.Playback.noSelection,
                artistName: displayedTrack?.artistName,
                statusText: statusText
            ),
            timeline: timeline,
            skipControls: timeline.map { _ in
                PlaybackSkipControlsView.Model(store)
            },
            controls: PlaybackControlsView.Model(store),
            utilityControls: PlaybackUtilityControlsView.Model(store),
            upNext: PlaybackUpNextView.Model(store)
        )
    }
}

extension PlaybackView.Model.Strings {
    /// Production localization wiring for transient playback presentation.
    static let localized = Self(
        loading: Locs.Playback.Status.loading,
        resourceUnavailable: Locs.Playback.Failure.resourceUnavailable,
        unsupportedResource: Locs.Playback.Failure.unsupportedResource,
        preparationFailed: Locs.Playback.Failure.preparationFailed,
        playbackFailed: Locs.Playback.Failure.playbackFailed
    )
}
