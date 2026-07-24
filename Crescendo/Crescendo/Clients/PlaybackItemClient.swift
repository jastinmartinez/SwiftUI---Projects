/// Loads one resolved resource into the shared playback implementation.
struct PlaybackItemClient: Sendable {
    var load: @Sendable (_ resource: PlaybackResource) async throws -> Void
}
