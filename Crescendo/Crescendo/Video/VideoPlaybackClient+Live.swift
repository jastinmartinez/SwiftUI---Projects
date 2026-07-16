import Foundation

extension VideoPlaybackClient {
    /// Coordinates an explicitly constructed item loader and playback session.
    @MainActor
    static func live(
        session: AVPlayerSession,
        itemLoader: VideoPlayableItemLoader
    ) -> Self {
        Self(
            load: { url in
                try await loadAndReplaceCurrentItem(
                    url,
                    itemLoader: itemLoader,
                    session: session
                )
            },
            pause: { await session.pause() },
            clear: { await session.clear() },
            seek: { await session.seek(to: $0) },
            playbackSnapshots: {
                await session.playbackSnapshots()
            }
        )
    }

    /// Keeps AVPlayerItem preparation and replacement on the main actor.
    @MainActor
    private static func loadAndReplaceCurrentItem(
        _ url: URL,
        itemLoader: VideoPlayableItemLoader,
        session: AVPlayerSession
    ) async throws {
        let item = try await itemLoader.load(url)
        try Task.checkCancellation()
        session.replaceCurrentItem(with: item)
    }
}
