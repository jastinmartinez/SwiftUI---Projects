import ComposableArchitecture
import Foundation

/// Captures one frozen target awaiting player identity confirmation.
struct PendingPlaybackTransition: Equatable {
    /// Distinguishes what confirming the target means for the confirmed queue.
    enum Origin: Equatable {
        /// A brand-new queue the user chose; confirmation installs it.
        case selection
        /// Movement inside the confirmed queue; confirmation only moves identity.
        case navigation
    }

    /// One mutually exclusive infrastructure settlement blocking transition
    /// work.
    enum Rollback: Equatable {
        case superseding(PlaybackItemInstallation)
        case abandoning(
            PlaybackItemInstallation,
            followUp: FollowUp
        )

        enum FollowUp: Equatable {
            case none
            case stop(requestID: UUID)
        }

        var installation: PlaybackItemInstallation {
            switch self {
            case .superseding(let installation),
                .abandoning(let installation, _):
                installation
            }
        }
    }

    let requestID: UUID
    let queue: IdentifiedArrayOf<Track>
    let targetTrackID: TrackID
    /// Defaults to the queue-installing meaning, which is the safe reading for
    /// any transition whose queue may not already be confirmed.
    var origin: Origin = .selection
    /// Records that the player has been handed the target item, so a snapshot
    /// bearing the target identity can no longer be describing the old item.
    var hasLoadedItem: Bool = false
    /// Delays new work or final teardown until a staged item is restored.
    var rollback: Rollback? = nil

    var installation: PlaybackItemInstallation? {
        rollback?.installation
            ?? (hasLoadedItem
                ? PlaybackItemInstallation(id: requestID)
                : nil)
    }
}
