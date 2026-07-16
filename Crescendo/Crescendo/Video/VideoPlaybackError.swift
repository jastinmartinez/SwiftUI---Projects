/// Normalizes video URL and playback failures for feature state.
enum VideoPlaybackError: Error, Equatable, Sendable {
    case emptyURL
    case invalidURL
    case unsupportedScheme
    case notPlayable
    case loadFailed
}
