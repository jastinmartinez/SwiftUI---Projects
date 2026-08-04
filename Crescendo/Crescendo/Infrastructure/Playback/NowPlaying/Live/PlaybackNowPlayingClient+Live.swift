@preconcurrency import MediaPlayer

extension PlaybackNowPlayingClient {
    /// Creates the production client that publishes confirmed playback to one
    /// explicitly supplied system information center.
    ///
    /// The client owns the Main Actor hop required by MediaPlayer. It does not
    /// inspect playback state or decide when presentation should be updated.
    ///
    /// - Parameter infoCenter: The system publication destination owned by the
    ///   application composition root.
    /// - Returns: Provider-neutral publication operations backed by MediaPlayer.
    @MainActor
    static func live(infoCenter: MPNowPlayingInfoCenter) -> Self {
        Self(
            publish: { projection in
                await MainActor.run {
                    infoCenter.nowPlayingInfo = projection.mediaPlayerInfo
                }
            },
            clear: {
                await MainActor.run {
                    infoCenter.nowPlayingInfo = nil
                }
            }
        )
    }
}
