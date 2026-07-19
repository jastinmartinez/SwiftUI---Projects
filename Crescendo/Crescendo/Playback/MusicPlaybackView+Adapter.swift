import ComposableArchitecture
import Foundation

extension MusicPlaybackView.Model {
    /// Adapts reducer-owned playback state and actions into presentation values.
    @MainActor
    init(_ store: StoreOf<MusicPlaybackFeature>, providerName: String?) {
        let snapshot = store.phase.snapshot
        let statusText: String
        switch store.phase {
        case .loading:
            statusText = Locs.MusicPlayback.Status.loading
        case .failed(.unavailable, _):
            statusText = Locs.MusicPlayback.Status.unavailable
        case .failed:
            statusText = Locs.MusicPlayback.Status.failed
        case .observing:
            switch snapshot.status {
            case .idle:
                statusText = Locs.MusicPlayback.Status.idle
            case .playing:
                statusText = Locs.MusicPlayback.Status.playing
            case .paused:
                statusText = Locs.MusicPlayback.Status.paused
            case .stopped:
                statusText = Locs.MusicPlayback.Status.stopped
            }
        }

        let timeline: MusicPlaybackTimelineView.Model? =
            store.selectedSong?.duration.flatMap { duration in
                guard store.capabilities.supportsSeeking, duration > 0 else {
                    return nil
                }
                let currentPosition: TimeInterval
                switch store.timeline.interaction {
                case .idle:
                    currentPosition = snapshot.currentTime
                case .dragging(let position), .seeking(_, let position):
                    currentPosition = position
                }
                let position = min(max(currentPosition, 0), duration)
                return MusicPlaybackTimelineView.Model(
                    position: position,
                    range: 0...duration,
                    elapsedTimeText: position.musicDurationText,
                    durationText: duration.musicDurationText,
                    onPositionChanged: {
                        store.send(.timeline(.positionChanged($0)))
                    },
                    onDragEnded: {
                        store.send(.timeline(.dragEnded))
                    }
                )
            }

        self.init(
            artworkURL: store.selectedSong?.artworkURL,
            metadata: MusicPlaybackMetadataView.Model(
                title: store.selectedSong?.title ?? Locs.MusicPlayback.noSelection,
                artistName: store.selectedSong?.artistName,
                providerAttribution: providerName.map(Locs.MusicPlayback.playingFrom),
                statusText: statusText
            ),
            timeline: timeline,
            controls: MusicPlaybackControlsView.Model(store),
            eligibility: PlaybackEligibilityNoticeView.Model(store)
        )
    }
}
