/// Describes whether a provider accepted a playback-navigation request.
enum PlaybackNavigationResult: Equatable, Sendable {
    case accepted
    case boundaryReached
}
