import Foundation

/// Defines the infrastructure-internal operation for loading optional Now
/// Playing image bytes.
///
/// The client isolates transport from system metadata publication. It does not
/// decode images, cache responses, inspect playback state, or expose image
/// bytes to reducers.
struct NowPlayingImageClient: Sendable {
    /// Loads the bytes referenced by one remote or managed-file image URL.
    var load: @Sendable (URL) async throws -> Data
}
