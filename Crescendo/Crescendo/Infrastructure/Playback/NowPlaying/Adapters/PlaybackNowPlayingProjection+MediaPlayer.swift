@preconcurrency import MediaPlayer

extension PlaybackNowPlayingClient.Projection {
    /// Translates confirmed playback presentation into the framework values
    /// consumed by `MPNowPlayingInfoCenter`.
    ///
    /// This adapter owns deterministic MediaPlayer key mapping only. It does
    /// not inspect reducer state, publish global state, or load artwork.
    var mediaPlayerInfo: [String: Any] {
        let trackID = item.id
        let externalContentIdentifier =
            "\(trackID.providerID.rawValue):\(trackID.nativeID)"
        let playbackRate: Double = transport.status == .playing ? 1 : 0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyExternalContentIdentifier:
                externalContentIdentifier,
            MPNowPlayingInfoPropertyMediaType:
                MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: timeline.position,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queue.index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
        ]

        if let artistName = item.artistName {
            info[MPMediaItemPropertyArtist] = artistName
        }
        if let albumTitle = item.albumTitle {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        if let duration = timeline.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        return info
    }
}
