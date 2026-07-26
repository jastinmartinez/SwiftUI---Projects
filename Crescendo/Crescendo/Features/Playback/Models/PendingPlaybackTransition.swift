import ComposableArchitecture
import Foundation

/// Captures one frozen target awaiting player identity confirmation.
struct PendingPlaybackTransition: Equatable {
    let requestID: UUID
    let queue: IdentifiedArrayOf<Track>
    let targetTrackID: TrackID
}
