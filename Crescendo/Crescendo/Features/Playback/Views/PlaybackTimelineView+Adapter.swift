import ComposableArchitecture
import Foundation

extension PlaybackTimelineView.Model {
    @MainActor
    init?(
        _ store: StoreOf<PlaybackFeature>,
        showsControls: Bool
    ) {
        guard let duration = store.queue.currentItem?.duration,
            duration > 0
        else { return nil }

        let position = min(max(store.timeline.position, 0), duration)
        let elapsedTimeText = position.musicDurationText
        let durationText = duration.musicDurationText
        let isEnabled = store.canRequestSeek

        self.init(
            slider: PlaybackSliderView.Model(
                value: position,
                scale: .init(range: 0...duration),
                accessibilityStep: 15,
                isEnabled: isEnabled,
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
            durationText: durationText,
            controls: showsControls
                ? [
                    Control(
                        id: .backward,
                        systemImage: "gobackward.15",
                        accessibilityLabel: Locs.Playback.backwardFifteenSeconds,
                        isEnabled: isEnabled,
                        perform: { store.send(.seekBackwardTapped) }
                    ),
                    Control(
                        id: .restart,
                        systemImage: "arrow.counterclockwise",
                        accessibilityLabel: Locs.Playback.restart,
                        isEnabled: isEnabled,
                        perform: { store.send(.restartTapped) }
                    ),
                    Control(
                        id: .forward,
                        systemImage: "goforward.15",
                        accessibilityLabel: Locs.Playback.forwardFifteenSeconds,
                        isEnabled: isEnabled,
                        perform: { store.send(.seekForwardTapped) }
                    ),
                ]
                : []
        )
    }
}
