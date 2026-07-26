import Foundation

/// Derives playback-command validity from confirmed state and pending workflows.
struct PlaybackCommandPolicy: Equatable {
    let capabilities: MusicProviderCapabilities
    let queue: PlaybackQueueFeature.State
    let status: PlaybackStatus
    let duration: TimeInterval?
    let pendingPlaybackTransition: PendingPlaybackTransition?
    let pendingStatusChange: PlaybackFeature.PendingStatusChange?
    let isResettingProvider: Bool

    /// Reports whether a command can begin from the represented domain state.
    ///
    /// Provider reset blocks every command before command-specific rules apply.
    ///
    /// - Parameter command: The playback operation the user is requesting.
    /// - Returns: `true` when the reducer may begin the requested operation.
    func allows(_ command: PlaybackCommand) -> Bool {
        guard !isResettingProvider else { return false }

        switch command {
        case .playPause:
            return capabilities.supportsEmbeddedPlayback
                && queue.currentTrackID != nil
                && pendingPlaybackTransition == nil
                && pendingStatusChange == nil
        case .stop:
            return capabilities.supportsEmbeddedPlayback
                && queue.currentTrackID != nil
                && status != .stopped
                && pendingStatusChange == nil
        case .seek:
            return capabilities.supportsSeeking
                && queue.currentTrackID != nil
                && duration.map { $0 > 0 } == true
                && pendingPlaybackTransition == nil
        case .previous:
            return pendingPlaybackTransition == nil
                && queue.previousTrackID != nil
        case .next:
            return pendingPlaybackTransition == nil
                && queue.nextTrackID != nil
        case .repeatMode, .shuffleMode:
            return pendingPlaybackTransition == nil
                && queue.currentTrackID != nil
        }
    }
}
