/// Describes whether a provider accepted a playback-navigation request.
enum PlaybackQueueNavigationResult: Equatable, Sendable {
    case accepted
    case boundaryReached
}
