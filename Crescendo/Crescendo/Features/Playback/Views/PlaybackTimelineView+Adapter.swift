import ComposableArchitecture
import Foundation

extension PlaybackTimelineView.Model {
    /// Adapts the confirmed duration and reducer-owned seek state into a timeline.
    @MainActor
    init?(_ store: StoreOf<PlaybackFeature>) {
        guard let duration = store.queue.currentItem?.duration,
            duration > 0
        else { return nil }

        let position = min(max(store.timeline.position, 0), duration)
        let elapsedTimeText = position.musicDurationText
        let durationText = duration.musicDurationText

        self.init(
            slider: PlaybackSliderView.Model(
                value: position,
                scale: .init(range: 0...duration),
                accessibilityStep: 15,
                isEnabled: store.canRequestSeek,
                strings: .init(
                    accessibilityLabel: Locs.Playback.position,
                    accessibilityValue: Locs.Playback.positionValue(
                        elapsedTime: elapsedTimeText,
                        durationTime: durationText
                    )
                ),
                onValueChanged: {
                    store.send(.timelinePositionChanged($0))
                },
                onInteractionEnded: {
                    store.send(.timelineInteractionEnded)
                }
            ),
            elapsedTimeText: elapsedTimeText,
            durationText: durationText
        )
    }
}
