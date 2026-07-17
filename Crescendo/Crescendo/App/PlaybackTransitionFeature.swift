import ComposableArchitecture

/// Holds the active provider playback operation owned by the application root.
@Reducer
enum PlaybackTransitionFeature {
    case musicStart(MusicStartFeature)
}

extension PlaybackTransitionFeature.State: Equatable {}
extension PlaybackTransitionFeature.Action: Equatable {}
