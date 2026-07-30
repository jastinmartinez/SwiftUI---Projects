import Foundation

/// Derives playback-command validity from confirmed state and pending workflows.
struct PlaybackCommandPolicy: Equatable {
    let hasConfirmedQueue: Bool
    let hasPreviousTrack: Bool
    let hasNextTrack: Bool
    let timelineDuration: TimeInterval?
    let isTimelineSeekable: Bool
    let sessionStatus: PlaybackStatus
    let hasPendingStatusChange: Bool
    let isTransitioning: Bool
    let transitionAcceptsStopRequest: Bool

    init(
        hasConfirmedQueue: Bool,
        hasPreviousTrack: Bool,
        hasNextTrack: Bool,
        timelineDuration: TimeInterval?,
        isTimelineSeekable: Bool,
        sessionStatus: PlaybackStatus,
        hasPendingStatusChange: Bool,
        isTransitioning: Bool,
        transitionAcceptsStopRequest: Bool
    ) {
        self.hasConfirmedQueue = hasConfirmedQueue
        self.hasPreviousTrack = hasPreviousTrack
        self.hasNextTrack = hasNextTrack
        self.timelineDuration = timelineDuration
        self.isTimelineSeekable = isTimelineSeekable
        self.sessionStatus = sessionStatus
        self.hasPendingStatusChange = hasPendingStatusChange
        self.isTransitioning = isTransitioning
        self.transitionAcceptsStopRequest = transitionAcceptsStopRequest
    }

    /// Creates a policy from feature states while discarding unrelated values,
    /// including the continuously changing timeline position.
    init(
        queue: PlaybackQueueReducer.State,
        timeline: PlaybackTimelineReducer.State,
        session: PlaybackSessionReducer.State,
        transition: PlaybackTransitionReducer.State?
    ) {
        self.init(
            hasConfirmedQueue: queue.current != nil,
            hasPreviousTrack: queue.current?.previousTrackID != nil,
            hasNextTrack: queue.current?.nextTrackID != nil,
            timelineDuration: timeline.duration,
            isTimelineSeekable: timeline.isSeekable,
            sessionStatus: session.status,
            hasPendingStatusChange: session.pendingStatusChange != nil,
            isTransitioning: transition != nil,
            transitionAcceptsStopRequest:
                transition?.acceptsStopRequest ?? true
        )
    }

    /// Reports whether a command can begin from the represented domain state.
    ///
    /// - Parameter command: The playback operation the user is requesting.
    /// - Returns: `true` when the reducer may begin the requested operation.
    func allows(_ command: PlaybackCommand) -> Bool {
        isAvailableOutsideTransition(command)
            && transitionAllows(command)
    }

    /// Describes how a control for the command may currently interact.
    ///
    /// - Parameter command: The playback operation represented by the control.
    /// - Returns: Whether the control is enabled, unavailable, or blocked only
    ///   by the active transition.
    func availability(
        for command: PlaybackCommand
    ) -> Availability {
        guard isAvailableOutsideTransition(command) else {
            return .disabled
        }
        guard transitionAllows(command) else {
            return isTransitioning ? .temporarilyBlocked : .disabled
        }
        return .enabled
    }

    private func isAvailableOutsideTransition(
        _ command: PlaybackCommand
    ) -> Bool {
        switch command {
        case .playPause:
            return hasConfirmedQueue
                && !hasPendingStatusChange
        case .stop:
            return hasConfirmedQueue
                && sessionStatus != .stopped
                && !hasPendingStatusChange
        case .seek:
            return isTimelineSeekable
                && hasConfirmedQueue
                && timelineDuration.map { $0 > 0 } == true
        case .previous:
            return hasPreviousTrack
        case .next:
            return hasNextTrack
        case .repeatMode, .shuffleMode:
            return hasConfirmedQueue
        }
    }

    private func transitionAllows(
        _ command: PlaybackCommand
    ) -> Bool {
        switch command {
        case .stop:
            return transitionAcceptsStopRequest
        case .playPause, .seek, .previous, .next, .repeatMode, .shuffleMode:
            return !isTransitioning
        }
    }
}

extension PlaybackCommandPolicy {
    enum Availability: Equatable {
        case enabled
        case disabled
        case temporarilyBlocked

        var isEnabled: Bool {
            self == .enabled
        }
    }
}
