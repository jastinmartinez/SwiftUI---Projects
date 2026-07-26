/// Derives playback-command validity from confirmed state and pending work.
struct PlaybackCommandPolicy: Equatable {
    let capabilities: MusicProviderCapabilities
    let queue: PlaybackQueueFeature.State
    let status: PlaybackStatus
    let pendingOperation: PlaybackFeature.PendingOperation?
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
            return allowsPlayPause
        case .stop:
            return allowsStop
        case .seek:
            return allowsSeek
        case .previous, .next:
            return allowsQueueTransition
        case .repeatMode:
            return allowsRepeatChange
        case .shuffleMode:
            return allowsShuffleChange
        }
    }
}

// swift-format-ignore: NoAccessLevelOnExtensionDeclaration
private extension PlaybackCommandPolicy {
    var allowsPlayPause: Bool {
        guard capabilities.supportsEmbeddedPlayback,
            !queue.tracks.isEmpty
        else { return false }

        switch pendingOperation {
        case .statusChange(let change):
            return change.target == .stopped
        case .queueReplacement:
            return false
        case nil:
            return true
        }
    }

    var allowsStop: Bool {
        guard capabilities.supportsEmbeddedPlayback else { return false }

        switch pendingOperation {
        case .queueReplacement:
            return true
        case .statusChange:
            return false
        case nil:
            return !queue.tracks.isEmpty && status != .stopped
        }
    }

    var allowsSeek: Bool {
        guard capabilities.supportsSeeking,
            let duration = queue.currentTrack?.duration
        else { return false }
        return duration > 0
    }

    var allowsQueueTransition: Bool {
        guard capabilities.supportsQueueTransitions,
            queue.currentTrackID != nil
        else { return false }
        guard case .queueReplacement = pendingOperation else {
            return true
        }
        return false
    }

    var allowsRepeatChange: Bool {
        guard queue.currentTrackID != nil,
            capabilities.supportedRepeatModes.count > 1
        else { return false }
        guard case .queueReplacement = pendingOperation else {
            return true
        }
        return false
    }

    var allowsShuffleChange: Bool {
        guard capabilities.supportsShuffle,
            queue.currentTrackID != nil
        else { return false }
        guard case .queueReplacement = pendingOperation else {
            return true
        }
        return false
    }
}
