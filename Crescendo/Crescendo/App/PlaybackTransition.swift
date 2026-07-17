/// Tracks the single parent-coordinated playback transition currently in flight.
enum PlaybackTransition: Equatable {
    case startingMusic(MusicItemID)
}
