@preconcurrency import AVFoundation

@MainActor
struct AVPlayerItemInstaller {
    let player: AVPlayer
    let registry: AVPlayerItemRegistry

    /// Commits a prepared item only while its originating task is current.
    ///
    /// - Parameters:
    ///   - item: The already validated player item.
    ///   - resource: The resource carrying the identity to observe later.
    /// - Throws: `CancellationError` when newer work cancelled installation.
    func install(
        _ item: AVPlayerItem,
        for resource: PlaybackResource
    ) throws {
        try Task.checkCancellation()
        let previousItem = player.currentItem
        registry.register(item, trackID: resource.trackID)
        player.replaceCurrentItem(with: item)
        if let previousItem {
            registry.remove(previousItem)
        }
    }
}
