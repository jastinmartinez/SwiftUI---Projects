/// Whether a requested playback operation reached its requested terminal state.
enum PlaybackOperationOutcome: Equatable, Sendable {
    case completed
    case interrupted
}
