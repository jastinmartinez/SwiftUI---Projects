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

    /// Makes item loading, play acceptance, and identity confirmation mutually
    /// exclusive so target evidence cannot outrun either prerequisite.
    enum ConfirmationReadiness: Equatable {
        /// The installer has not returned yet. Matching observations remain
        /// transaction-local and only the newest one is retained.
        case awaitingLoad(latestTargetSnapshot: PlaybackSnapshot?)
        /// The item is installed, but the transport has not accepted play yet.
        case awaitingPlay(latestTargetSnapshot: PlaybackSnapshot?)
        /// Play returned successfully, so target identity may enter settlement.
        case readyForConfirmation
    }

    /// One mutually exclusive infrastructure settlement phase.
    enum Settlement: Equatable {
        case none
        case rollingBack(Rollback)
        case committing(Commit)
        case applyingCommit(Commit)
    }

    struct Commit: Equatable {
        var snapshot: PlaybackSnapshot
        var followUp: FollowUp? = nil
    }

    enum FollowUp: Equatable {
        case transition(TransitionIntent)
        case stop(requestID: UUID)
    }

    struct TransitionIntent: Equatable {
        let requestID: UUID
        let queue: IdentifiedArrayOf<Track>
        let targetTrackID: TrackID
        let origin: Origin
    }

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
    /// Keeps target evidence out of confirmed state until load and play return.
    var confirmationReadiness: ConfirmationReadiness =
        .awaitingLoad(latestTargetSnapshot: nil)
    /// Retains ownership until commit or rollback settlement is fully applied.
    var settlement: Settlement = .none

    var installation: PlaybackItemInstallation {
        PlaybackItemInstallation(id: requestID)
    }

    var rollbackInstallation: PlaybackItemInstallation {
        guard case .rollingBack(let rollback) = settlement else {
            return installation
        }
        return rollback.installation
    }

    var canAdvance: Bool {
        settlement == .none
    }

    mutating func discardPendingTargetSnapshot() {
        switch confirmationReadiness {
        case .awaitingLoad:
            confirmationReadiness =
                .awaitingLoad(latestTargetSnapshot: nil)
        case .awaitingPlay:
            confirmationReadiness =
                .awaitingPlay(latestTargetSnapshot: nil)
        case .readyForConfirmation:
            break
        }
    }

    mutating func retainLatestFollowUp(_ followUp: FollowUp) -> Bool {
        switch settlement {
        case .committing(var commit):
            commit.followUp = followUp
            settlement = .committing(commit)
            return true
        case .applyingCommit(var commit):
            commit.followUp = followUp
            settlement = .applyingCommit(commit)
            return true
        case .none, .rollingBack:
            return false
        }
    }
}
