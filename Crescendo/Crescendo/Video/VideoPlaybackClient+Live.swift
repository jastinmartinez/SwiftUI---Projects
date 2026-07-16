import Foundation

extension VideoPlaybackClient {
    /// Coordinates an explicitly constructed item loader and playback controller.
    @MainActor
    static func live(
        controller: AVPlayerController,
        itemLoader: VideoPlayableItemLoader
    ) -> Self {
        Self(
            load: { url in
                try await loadAndReplaceCurrentItem(
                    url,
                    itemLoader: itemLoader,
                    controller: controller
                )
            },
            pause: { await controller.pause() },
            clear: { await controller.clear() },
            seek: { await controller.seek(to: $0) },
            playbackSnapshots: {
                await controller.playbackSnapshots()
            }
        )
    }

    /// Keeps AVPlayerItem preparation and replacement on the main actor.
    @MainActor
    private static func loadAndReplaceCurrentItem(
        _ url: URL,
        itemLoader: VideoPlayableItemLoader,
        controller: AVPlayerController
    ) async throws {
        let item = try await itemLoader.load(url)
        try Task.checkCancellation()
        controller.replaceCurrentItem(with: item)
    }
}
