import ComposableArchitecture
import Foundation

extension PlaybackView.Model {
    /// Projects reducer-owned playback state into the expanded-player presentation.
    ///
    /// Pending transport targets take precedence over confirmed status, while
    /// timeline-dependent sections are omitted when no valid duration exists.
    ///
    /// - Parameters:
    ///   - store: The playback store supplying domain state and receiving callbacks.
    ///   - providerName: The connected provider name shown as attribution, or `nil`
    ///     when no attribution should be rendered.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>, providerName: String?) {
        let statusText: String
        if case .statusChange(let change) = store.pendingOperation {
            switch change.target {
            case .playing:
                statusText = Locs.Playback.Status.playing
            case .paused:
                statusText = Locs.Playback.Status.paused
            case .stopped:
                statusText = Locs.Playback.Status.stopped
            }
        } else if store.pendingOperation != nil {
            statusText = Locs.Playback.Status.loading
        } else if store.failure == .unavailable {
            statusText = Locs.Playback.Status.unavailable
        } else if store.failure != nil {
            statusText = Locs.Playback.Status.failed
        } else {
            switch store.status {
            case .idle:
                statusText = Locs.Playback.Status.idle
            case .playing:
                statusText = Locs.Playback.Status.playing
            case .paused:
                statusText = Locs.Playback.Status.paused
            case .stopped:
                statusText = Locs.Playback.Status.stopped
            }
        }

        let song = store.queue.currentItem

        let timeline = PlaybackTimelineView.Model(store)

        self.init(
            artworkURL: song?.artworkURL,
            metadata: PlaybackMetadataView.Model(
                title: song?.title ?? Locs.Playback.noSelection,
                artistName: song?.artistName,
                providerAttribution: providerName.map(Locs.Playback.playingFrom),
                statusText: statusText
            ),
            timeline: timeline,
            skipControls: timeline.map { _ in
                PlaybackSkipControlsView.Model(store)
            },
            controls: PlaybackControlsView.Model(store),
            utilityControls: PlaybackUtilityControlsView.Model(store),
            eligibility: PlaybackEligibilityNoticeView.Model(store)
        )
    }
}
