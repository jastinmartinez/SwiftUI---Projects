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

    let requestID: UUID
    let queue: IdentifiedArrayOf<Track>
    let targetTrackID: TrackID
    /// Defaults to the queue-installing meaning, which is the safe reading for
    /// any transition whose queue may not already be confirmed.
    var origin: Origin = .selection
    /// Records that the player has been handed the target item, so a snapshot
    /// bearing the target identity can no longer be describing the old item.
    var hasLoadedItem: Bool = false
}
