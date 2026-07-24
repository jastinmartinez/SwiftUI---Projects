enum PlaybackFailure: Error, Equatable, Sendable {
    case resourceUnavailable
    case unsupportedResource
    case preparationFailed
    case playbackFailed
}
