import ComposableArchitecture
import Foundation

extension PlaybackView.Model {
    /// Adapts reducer-owned playback state and actions into presentation values.
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
