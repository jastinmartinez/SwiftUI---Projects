import ComposableArchitecture
import Foundation

extension PlaybackView.Model {
    /// Adapts reducer-owned playback state and actions into presentation values.
    @MainActor
    init(_ store: StoreOf<PlaybackFeature>, providerName: String?) {
        let snapshot = store.phase.snapshot
        let statusText: String
        switch store.phase {
        case .loading:
            statusText = Locs.Playback.Status.loading
        case .failed(.unavailable, _):
            statusText = Locs.Playback.Status.unavailable
        case .failed:
            statusText = Locs.Playback.Status.failed
        case .observing:
            switch snapshot.status {
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

        let timeline = PlaybackTimelineView.Model.make(
            duration: store.selectedSong?.duration,
            snapshot: snapshot,
            timeline: store.timeline,
            supportsSeeking: store.capabilities.supportsSeeking,
            strings: { elapsedTime, durationTime in
                .localized(
                    elapsedTime: elapsedTime,
                    durationTime: durationTime
                )
            },
            onPositionChanged: {
                store.send(.timeline(.positionChanged($0)))
            },
            onDragEnded: {
                store.send(.timeline(.dragEnded))
            }
        )

        self.init(
            artworkURL: store.selectedSong?.artworkURL,
            metadata: PlaybackMetadataView.Model(
                title: store.selectedSong?.title ?? Locs.Playback.noSelection,
                artistName: store.selectedSong?.artistName,
                providerAttribution: providerName.map(Locs.Playback.playingFrom),
                statusText: statusText
            ),
            timeline: timeline,
            controls: PlaybackControlsView.Model(store),
            eligibility: PlaybackEligibilityNoticeView.Model(store)
        )
    }
}

extension PlaybackTimelineView.Model.Strings {
    static func localized(
        elapsedTime: String,
        durationTime: String
    ) -> Self {
        Self(
            accessibilityLabel: Locs.Playback.position,
            accessibilityValue: Locs.Playback.positionValue(
                elapsedTime: elapsedTime,
                durationTime: durationTime
            )
        )
    }
}
