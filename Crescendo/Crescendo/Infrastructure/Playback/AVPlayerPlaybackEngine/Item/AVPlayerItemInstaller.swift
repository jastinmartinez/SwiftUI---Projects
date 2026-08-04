@preconcurrency import AVFoundation

@MainActor
final class AVPlayerItemInstaller {
    private struct StagedInstallation {
        let token: PlaybackItemInstallation
        let targetItem: AVPlayerItem
        let previousItem: AVPlayerItem?
    }

    let player: AVPlayer
    let registry: AVPlayerItemRegistry
    private var stagedInstallation: StagedInstallation?

    init(player: AVPlayer, registry: AVPlayerItemRegistry) {
        self.player = player
        self.registry = registry
    }

    /// Stages a prepared item only while its originating task is current.
    ///
    /// - Parameters:
    ///   - item: The already validated player item.
    ///   - trackID: The identity observations report for the installed item.
    ///   - installation: The reducer-correlated installation identity.
    /// - Throws: `CancellationError` when newer work cancelled installation.
    func install(
        _ item: AVPlayerItem,
        trackID: TrackID,
        installation: PlaybackItemInstallation
    ) throws {
        try Task.checkCancellation()
        let previousItem =
            stagedInstallation?.previousItem ?? player.currentItem
        if let stagedInstallation {
            registry.remove(stagedInstallation.targetItem)
        }
        registry.register(item, trackID: trackID)
        player.replaceCurrentItem(with: item)
        stagedInstallation = StagedInstallation(
            token: installation,
            targetItem: item,
            previousItem: previousItem
        )
    }

    /// Makes a staged target permanent without letting stale work touch newer
    /// staged installation state.
    ///
    /// - Parameter installation: The correlation identity that must match the
    ///   currently staged item.
    func commit(_ installation: PlaybackItemInstallation) {
        guard let stagedInstallation,
            stagedInstallation.token == installation
        else { return }
        if let previousItem = stagedInstallation.previousItem {
            registry.remove(previousItem)
        }
        self.stagedInstallation = nil
    }

    /// Restores the prior item only when the token still identifies the newest
    /// staged installation.
    ///
    /// - Parameter installation: The correlation identity that must match the
    ///   currently staged item before restoration.
    func rollback(_ installation: PlaybackItemInstallation) {
        guard let stagedInstallation,
            stagedInstallation.token == installation
        else { return }

        player.replaceCurrentItem(with: stagedInstallation.previousItem)
        registry.remove(stagedInstallation.targetItem)
        self.stagedInstallation = nil
    }
}
