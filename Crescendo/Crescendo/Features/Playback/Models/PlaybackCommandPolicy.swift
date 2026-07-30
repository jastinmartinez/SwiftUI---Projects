import Foundation

/// Derives playback-command validity from confirmed state and pending workflows.
struct PlaybackCommandPolicy: Equatable {
    let queue: PlaybackQueueFeature.State
    let timeline: PlaybackTimelineFeature.State
    let session: PlaybackSessionFeature.State
    let transition: PlaybackTransitionFeature.State?

    /// Reports whether a command can begin from the represented domain state.
    ///
    /// - Parameter command: The playback operation the user is requesting.
    /// - Returns: `true` when the reducer may begin the requested operation.
    func allows(_ command: PlaybackCommand) -> Bool {
        switch command {
        case .playPause:
            return queue.current != nil
                && transition == nil
                && session.pendingStatusChange == nil
        case .stop:
            return queue.current != nil
                && session.status != .stopped
                && session.pendingStatusChange == nil
        case .seek:
            return timeline.isSeekable
                && queue.current != nil
                && timeline.duration.map { $0 > 0 } == true
                && transition == nil
        case .previous:
            return transition == nil
                && queue.current?.previousTrackID != nil
        case .next:
            return transition == nil
                && queue.current?.nextTrackID != nil
        case .repeatMode, .shuffleMode:
            return transition == nil
                && queue.current != nil
        }
    }
}
